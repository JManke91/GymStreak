//
//  WatchMarqueeText.swift
//  GymStreakWatch Watch App
//
//  A single-line label that scrolls its own overflow through a fixed-width slot
//  instead of ellipsizing it away.
//
//  Why this exists (and why plain truncation was not good enough): German
//  exercise names routinely exceed the name slot in the active-workout top zone,
//  which shares its row with the "Set X/Y" counter. Measured against the shipped
//  German seed catalog, 47 of 96 names overflow the ~18-character budget, and the
//  longest ("Kreuzheben mit gestreckten Beinen", 33 chars) cannot be made to fit
//  at ANY legible size on a 184–208 pt screen — so no static layout solves this.
//
//  Worse, tail truncation removes precisely the disambiguating token: ten seed
//  name groups differ ONLY in their trailing qualifier ("Kniebeuge (Langhantel)"
//  vs "Kniebeuge (Multipresse)", "Bankdrücken" × Langhantel/Kurzhantel/
//  Multipresse, …). A truncated tail renders two genuinely different exercises
//  identically, which is the actual user-facing bug. It also rules out the
//  tempting "drop the parenthetical first" fix — that discards the only bytes
//  that carry meaning here.
//
//  There is no built-in marquee on watchOS. Verified via ios-api-researcher
//  against Apple's docs: no SwiftUI modifier scrolls overflowing `Text`;
//  `.truncationMode`/`.allowsTightening`/`.lineLimit(_:reservesSpace:)` are all
//  static, `ViewThatFits` picks a variant once, and the Now Playing marquee is
//  private system chrome with no public equivalent. `WKInterfaceLabel` is static
//  AND unreachable from a SwiftUI-lifecycle watch app. So this is hand-built.
//
//  Design of the cycle — it is deliberately head-dominant. The head is what a
//  glance lands on most of the time, so the resting state stays byte-identical
//  to the old static label and mid-set glances keep reading the same familiar
//  prefix. Only the surplus travels, once per cycle, at a readable crawl.
//

import SwiftUI

/// Pacing and geometry for one marquee cycle.
///
/// A pure value type on purpose: the "should this move at all" rule and the
/// travel timing are the parts worth pinning down in tests, and neither needs a
/// view host to evaluate. See `WatchMarqueeTextTests`.
struct WatchMarqueeCycle: Equatable {
    /// Points of text hidden past the slot's trailing edge (natural − slot).
    let overflow: CGFloat
    /// Width of the slot the text has to live in.
    let slotWidth: CGFloat

    /// The scale floor the static label used before it could scroll. Overflow
    /// this can still absorb is absorbed — nothing should slide for three points.
    static let scaleFloor: CGFloat = 0.85
    /// Constant scroll speed. Slow enough to read a German compound word,
    /// brisk enough that the longest seed name completes inside one cycle.
    static let pointsPerSecond: CGFloat = 32
    /// The resting state, held long because most glances land here.
    static let headDwell: Double = 2.2
    /// Long enough to finish reading the qualifier that just arrived.
    static let tailDwell: Double = 1.4
    /// Snapping back is a return-to-rest, not content the user reads, so it is
    /// eased and quick rather than another readable pass.
    static let returnDuration: Double = 0.45

    /// Overflow that shrinking to `scaleFloor` would still absorb.
    ///
    /// A label of natural width `W` in a slot `S` fits at scale `f` when
    /// `W · f ≤ S`; with `f ≥ scaleFloor` that holds exactly while
    /// `W − S ≤ S · (1/scaleFloor − 1)`.
    var absorbableOverflow: CGFloat {
        max(0, slotWidth * (1 / Self.scaleFloor - 1))
    }

    /// Whether the surplus is big enough that scaling can no longer rescue it.
    /// Below this the label just shrinks, exactly as it did before.
    var scrolls: Bool {
        slotWidth > 0 && overflow > absorbableOverflow
    }

    /// Seconds of travel for the surplus at the fixed crawl speed.
    var travelDuration: Double {
        guard scrolls else { return 0 }
        return Double(overflow / Self.pointsPerSecond)
    }

    /// Full head → tail → head period, for tests and for reasoning about pacing.
    var cycleDuration: Double {
        guard scrolls else { return 0 }
        return Self.headDwell + travelDuration + Self.tailDwell + Self.returnDuration
    }
}

/// Single-line label that scrolls its overflow instead of ellipsizing it.
///
/// Drops into any slot a plain `Text` would occupy: it claims exactly the width
/// a truncating `Text` would claim, so surrounding layout is unchanged.
///
/// **Use one at a time — never in a `List` or `ForEach` row.** Each instance costs
/// three text measurements, a long-lived `Task` and a repeating animation; per row
/// that is exactly the per-item cost the project's rendering rules prohibit. This
/// is for a single prominent label in a fixed slot.
struct WatchMarqueeText: View {
    let text: String
    let font: Font
    /// Passed in rather than inherited from the call site's `.foregroundStyle`.
    /// The layout owner below must be invisible, and relying on an overlay to
    /// escape an ancestor's foreground style is exactly the kind of subtlety that
    /// renders a label invisible if the semantics differ from what you assumed.
    /// An explicit colour makes that unrepresentable.
    let color: Color

    /// Motion is not the only way to read this label — VoiceOver already speaks
    /// the untruncated name — so both of these fall back to the plain ellipsized
    /// label rather than to a frozen half-scrolled one.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Wrist-down / Always-On. The system throttles refresh to ~1 Hz here, so an
    /// animation would neither read well nor be honoured; parking at the head
    /// also guarantees a dimmed glance never catches a frozen middle substring.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var slotWidth: CGFloat = 0
    @State private var naturalWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var cycle: WatchMarqueeCycle {
        WatchMarqueeCycle(overflow: naturalWidth - slotWidth, slotWidth: slotWidth)
    }

    private var isAnimating: Bool {
        cycle.scrolls && !reduceMotion && !isLuminanceReduced
    }

    /// Restarts the cycle when the exercise changes, and tears it down the moment
    /// motion becomes unwanted (Reduce Motion toggled, wrist lowered).
    ///
    /// Deliberately does NOT include the overflow. Overflow is animated geometry —
    /// an ancestor animates on `currentExerciseIndex`/`currentSetIndex`, so the slot
    /// width interpolates and `onGeometryChange` reports every intermediate frame.
    /// Keying on it cancelled and recreated the task a dozen times per transition.
    /// It is also unnecessary: `runCycle()` re-reads `cycle` on each pass, so the
    /// travel distance already tracks the current geometry.
    private var cycleIdentity: String {
        "\(text)|\(isAnimating)"
    }

    var body: some View {
        // A hidden copy owns the layout. It compresses like any truncating `Text`,
        // so it hands the row its width, its height AND its first text baseline —
        // the reason this is not a `GeometryReader`, which has no baseline and
        // would break the name/"Set X/Y" `.firstTextBaseline` alignment.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { slotWidth = $0 }
            .background(alignment: .leading) { naturalWidthProbe }
            // Baseline, not centre: in the shrink band the visible label carries
            // `minimumScaleFactor` and the layout owner does not, so a centred
            // overlay could sit a fraction off the row's baseline. This makes the
            // alignment the row depends on unconditional.
            .overlay(alignment: .leadingFirstTextBaseline) { visibleLabel }
            .clipped()
            .task(id: cycleIdentity) { await runCycle() }
    }

    /// The text the user actually sees.
    ///
    /// `fixedSize` is the switch between the two behaviours: on, the label renders
    /// at full natural width and is clipped by the parent so `offset` can slide it;
    /// off, it is proposed the slot width and truncates with a normal ellipsis —
    /// byte-identical to the pre-marquee label, which is what Reduce Motion and
    /// Always-On get. `minimumScaleFactor` still handles the near-fits that never
    /// reach the scroll threshold.
    private var visibleLabel: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(WatchMarqueeCycle.scaleFloor)
            .foregroundStyle(color)
            .fixedSize(horizontal: isAnimating, vertical: false)
            .offset(x: offset)
    }

    /// An unconstrained copy, measured but never drawn, to learn the width the
    /// text WANTS. Overflow is that minus the slot.
    private var naturalWidthProbe: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { naturalWidth = $0 }
            .accessibilityHidden(true)
    }

    /// head dwell → travel → tail dwell → return, repeating until cancelled.
    ///
    /// Sequenced with `Task.sleep` rather than a `repeatForever` animation because
    /// the dwells at each end are the point: a single repeating animation cannot
    /// hold still at the head, and holding still at the head is what keeps a
    /// two-second glance reading the same prefix it always did.
    private func runCycle() async {
        // FIRST, unconditionally — before the `isAnimating` check and before the
        // opening dwell. `offset` is `@State` on a view instance that SURVIVES an
        // exercise change: the set editor swaps the name through a computed
        // `displayedExercise` rather than re-pushing the screen, so nothing resets
        // it for us. Without this, advancing from one long name to the next drew
        // the NEW name at the OLD name's scroll offset — almost entirely off its
        // own head — for the full 2.2 s opening dwell, then animated backwards if
        // the new name was shorter.
        settleAtHead()
        guard isAnimating else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(WatchMarqueeCycle.headDwell))
            guard !Task.isCancelled else { break }

            withAnimation(.linear(duration: cycle.travelDuration)) {
                offset = -cycle.overflow
            }
            try? await Task.sleep(for: .seconds(cycle.travelDuration + WatchMarqueeCycle.tailDwell))
            guard !Task.isCancelled else { break }

            withAnimation(.easeInOut(duration: WatchMarqueeCycle.returnDuration)) {
                offset = 0
            }
            try? await Task.sleep(for: .seconds(WatchMarqueeCycle.returnDuration))
        }
    }

    /// Park at the head with animation suppressed — a cancelled cycle can leave an
    /// in-flight linear animation behind, and letting it finish would slide the
    /// label while the screen is dimmed or Reduce Motion is on.
    private func settleAtHead() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0 }
    }
}

#Preview("Marquee — overflowing vs fitting") {
    ZStack {
        OnyxWatch.Colors.background.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 18) {
            ForEach(
                [
                    "Kreuzheben mit gestreckten Beinen",
                    "Kniebeuge (Langhantel)",
                    "Bankdrücken",
                ],
                id: \.self
            ) { name in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    WatchMarqueeText(
                        text: name,
                        font: .system(size: 15, weight: .bold),
                        color: OnyxWatch.Colors.textPrimary
                    )
                    Spacer(minLength: 6)
                    Text("Set 2/3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OnyxWatch.Colors.textMuted)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 8)
    }
}
