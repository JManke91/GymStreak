//
//  RestDurationAdjustmentChrome.swift
//  GymStreakWatch Watch App
//
//  The editing treatment of the large rest timer: everything that appears while
//  the Digital Crown is changing the rest duration. Split out of
//  RestTimerLargeView, which owns the Crown itself.
//
//  Neither piece takes layout space of its own — this screen has none to give.
//  The badge is an OVERLAY on the "REST" caption, and the footer BORROWS the
//  Minimize/Skip slot, cross-fading with the buttons while the Crown turns.
//  That is what keeps the digits exactly where they are when an adjustment
//  starts. See `docs/watch-rest-timer-ui.md` for the two layouts that were
//  tried first and why each failed on a real 46 mm watch.
//

import SwiftUI

enum RestAdjustmentChrome {
    static let crossfade: TimeInterval = 0.12

    /// How long the Crown hint owns the caption slot at the start of a rest.
    /// The design's "Crown-Hinweis nur in den ersten 2 s" — long enough to be
    /// read, short enough that it is gone before anyone looks for the label.
    static let crownHintLife: TimeInterval = 2

    static func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The one caption line above the countdown, in its four states: the `+15 s`
/// badge while adjusting, the Crown hint in the first seconds of a rest, the
/// next set's target, and "REST" as the fallback.
///
/// The first two are drawn *over* the line, so they may be wider and taller
/// without moving anything below; the last two swap the line itself, at one
/// font, so neither changes its height. That is the whole reason this slot
/// carries all four: it is the only place on this screen where something can
/// appear for free (see `docs/watch-rest-timer-ui.md`, "The vertical budget"),
/// and "REST" is the one line that says nothing the countdown below it has not
/// already said — which is exactly what makes it affordable to spend on the
/// next set's target.
struct RestAdjustmentCaption: View {
    let isAdjusting: Bool
    let delta: TimeInterval
    /// Advertise the Crown. Loses to `isAdjusting` — once the user is turning
    /// it, the delta is the more useful thing to show in the same slot.
    let showsCrownHint: Bool
    /// What the upcoming set asks for, e.g. `"80 kg × 8"`, rendered after a
    /// tinted dumbbell. Takes the slot from
    /// "REST" whenever it exists — which is always, in practice; a rest never
    /// starts with no set left to rest for. Loses to both overlays above, and
    /// the Crown hint keeps its two seconds: turning the Crown is an otherwise
    /// invisible gesture, and the next set matters most later in the countdown.
    let nextSetTarget: String?

    var body: some View {
        captionLine
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            // Applied here, before `.overlay`, so it governs the LAYOUT element
            // and not the two overlays — which set their own (the hint clamps
            // its Dynamic Type, the badge is `fixedSize`). Being the layout
            // element is what lets this work at all: the line is proposed the
            // column's full width and scales down inside it, where an overlay
            // needs `fixedSize()` to escape the caption's width and so can only
            // grow.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .opacity(isAdjusting || showsCrownHint ? 0 : 1)
            .overlay {
                if isAdjusting {
                    deltaText
                        .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(OnyxWatch.Colors.textOnTint)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(OnyxWatch.Colors.tint, in: Capsule())
                        .transition(.opacity)
                } else if showsCrownHint {
                    crownHint
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
            .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: showsCrownHint)
    }

    /// The layout element. Both states share the caption font, so exchanging one
    /// for the other cannot move the countdown — the acceptance bar for anything
    /// added to this column.
    ///
    /// Exact while nothing is scaling. In the widest case (40 mm, German,
    /// `220,5 lb × 12`) `minimumScaleFactor` shrinks the value and its line box
    /// with it, so the caption can become a point or two *shorter* than the
    /// "REST" fallback. The countdown then moves up, never down — the safe
    /// direction, and the reason this is a note rather than a defect.
    ///
    /// The single-line guarantee lives here rather than on either branch, so
    /// both get it. "REST" needs it more than it looks: it carries
    /// `tracking(1.5)` and is the branch that could genuinely wrap to two lines
    /// at the accessibility text sizes and push the countdown down.
    @ViewBuilder
    private var captionLine: some View {
        if let nextSetTarget {
            nextSet(nextSetTarget)
        } else {
            Text("Rest")
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)
        }
    }

    /// `Next  ⬮ 80 kg × 8` — a quiet label, the tinted dumbbell, the target.
    ///
    /// The value is styled as a sibling of the HR/kCal row two lines above it —
    /// `WorkoutMetricsView` in `ExerciseListView.swift`, which is the screen's
    /// own idiom for "here is a number and what it measures": a **coloured
    /// glyph** (`heart.fill` red, `flame` orange — so `dumbbell.fill` tint),
    /// then the **value bold**, then a small `.secondary` word ("BPM", "kCal").
    /// This line reorders that last part, putting the naming word first because
    /// it names the whole line rather than a unit. Two earlier versions are
    /// worth recording because each failed in a way the next one fixed:
    ///
    /// 1. A grey `arrow.right` and a grey value. Read as stray text — an arrow
    ///    and a number, with nothing saying what either meant.
    /// 2. The glyph and colour above, but no words. Much better, and still not
    ///    self-evident: a dumbbell says *exercise*, not *the set you are about
    ///    to do*.
    ///
    /// **The label is deliberately the cheapest element on the line**, in both
    /// senses. It is a *fixed* cost against a *variable* payload — the same
    /// width whether the value is `8 Wdh.` or `220,5 lb × 12` — so it is drawn
    /// two type steps below the value (`.caption2` against `.footnote`) to keep
    /// the number dominant, and it is kept to one short word per language:
    /// "Next" / "Als Nächstes", not "Next set:" / "Nächster Satz:", which was
    /// the first version and spent ~25 pt of a ~142 pt line on a label nobody
    /// re-reads. If this line ever has to give more back, dropping the glyph is
    /// the cheapest ≈19 pt available now that the word carries its meaning.
    ///
    /// The glyph stays a type step below the *value* for a harder reason. Unlike
    /// the two overlays this is the **layout** element, so anything whose box is
    /// taller than the value's line height would push the countdown down — the
    /// one thing this column cannot absorb.
    private func nextSet(_ target: String) -> some View {
        HStack(spacing: 4) {
            Text("Next")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "dumbbell.fill")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(OnyxWatch.Colors.tint)
                // Decorative, exactly like the Crown hint's glyph: the countdown
                // speaks the whole target in its own accessibility value, and
                // the label beside it is spoken there too.
                .accessibilityHidden(true)
            Text(target)
                .foregroundStyle(.primary)
                // Both Texts inherit `minimumScaleFactor` and would otherwise
                // scale INDEPENDENTLY against whatever width the stack proposes
                // each of them — nothing would make the shrink land on the
                // label rather than on the number, and the intended hierarchy
                // could invert in exactly the widest case it exists for. The
                // value keeps its width; the label gives.
                .layoutPriority(1)
        }
    }

    /// Turning the Crown here is a completely invisible gesture — nothing on the
    /// screen suggests the countdown is editable — so the caption spends the
    /// first `crownHintLife` seconds of every rest saying so. The design's
    /// "Drehen = Dauer" (frame A1).
    private var crownHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "digitalcrown.arrow.clockwise")
            Text("Turn = duration")
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(OnyxWatch.Colors.tint)
        .lineLimit(1)
        // An overlay is proposed its BASE view's size, so without this the hint
        // would be squeezed into the width of "REST".
        .fixedSize()
        // …and `fixedSize` means it can only grow — at the accessibility text
        // sizes it would run off both display edges. Clamping beats truncating
        // for a two-second decoration, and VoiceOver never sees it: it is hidden
        // here, and the countdown already carries an `accessibilityHint` saying
        // the same thing.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }

    private var deltaText: Text {
        let seconds = Int(delta.rounded())
        return seconds < 0 ? Text("−\(abs(seconds)) s") : Text("+\(seconds) s")
    }
}

/// The tick track and the `1:30 → 1:45` line under the digits.
///
/// Meant to be attached with `.restAdjustmentFooter(...)`, which hangs it in the
/// gap below the countdown without giving it any layout space.
struct RestAdjustmentFooter: View {
    let isAdjusting: Bool
    /// The duration the adjustment started from.
    let baseline: TimeInterval
    let current: TimeInterval
    let step: TimeInterval

    /// Bounded literal set — safe in a plain `HStack`.
    private static let tickCount = 25
    private static let tickWidth: CGFloat = 1.5
    private static let tickSpacing: CGFloat = 6

    var body: some View {
        // Built only while adjusting: this sits inside a body that re-evaluates
        // every second from the countdown and 5–10×/s during a rotation, so the
        // 25 capsules, the gradient mask and the formatting must not be
        // constructed just to be hidden.
        ZStack {
            if isAdjusting {
                VStack(spacing: 4) {
                    tickTrack
                    Text("\(RestAdjustmentChrome.durationText(baseline)) → \(RestAdjustmentChrome.durationText(current))")
                        .font(.system(.caption2, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
        .accessibilityHidden(true)
        // Decorative, and it is drawn OUTSIDE its host's bounds in the gap just
        // above the Minimize/Skip row — SwiftUI hit-tests at rendered position,
        // not at the declared layout box, so without this the ruler could
        // swallow a button tap during the fade-out.
        .allowsHitTesting(false)
    }

    /// A ruler that slides one notch per detent, so the size of the change is
    /// legible without reading the numbers.
    private var tickTrack: some View {
        HStack(spacing: Self.tickSpacing) {
            ForEach(0..<Self.tickCount, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index.isMultiple(of: 5) ? 0.85 : 0.3))
                    .frame(width: Self.tickWidth, height: index.isMultiple(of: 5) ? 8 : 5)
            }
        }
        .offset(x: tickOffset)
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .clipped()
        .mask {
            LinearGradient(
                colors: [.clear, .white, .white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay {
            Capsule()
                .fill(OnyxWatch.Colors.tint)
                .frame(width: 2, height: 10)
        }
    }

    /// Wrapped over the five-tick group so the track can scroll indefinitely
    /// without running out of ticks.
    private var tickOffset: CGFloat {
        guard step > 0 else { return 0 }
        let pitch = Self.tickWidth + Self.tickSpacing
        let steps = (current - baseline) / step
        return (-CGFloat(steps) * pitch).truncatingRemainder(dividingBy: pitch * 5)
    }
}

/// The "This rest / All sets" confirmation that springs in below the countdown
/// a moment after the Crown settles.
///
/// It is a **confirmation, never a blocker**: it preselects what already
/// happened (`allSets` — ticket 01 wrote the new duration to every set), lives
/// for `life` seconds and slides away leaving the choice in effect. The user can
/// ignore it, skip the rest or minimize the timer straight through it.
///
/// It is mutually exclusive with the editing chrome above — see
/// `RestDurationCrownAdjustment` for why (this screen cannot afford both).
struct RestScopeRow: View {
    let selection: WatchWorkoutViewModel.RestAdjustmentScope
    let onSelect: (WatchWorkoutViewModel.RestAdjustmentScope) -> Void

    /// The spring the row arrives and leaves on.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// How long it stays up with no input.
    static let life: TimeInterval = 3

    var body: some View {
        HStack(spacing: 2) {
            option(.thisRestOnly, title: "This rest")
            option(.allSets, title: "All sets")
        }
        .padding(2)
        .background(OnyxWatch.Colors.chipBackground, in: Capsule())
        // Asymmetric on purpose. A removal transition holds the view's layout
        // slot until it finishes, so an animated exit would leave the row's
        // ~27 pt in the column while the caption reclaims its own — the two
        // overlapping is exactly what this screen has no room for. Springing in
        // is free (the caption's slot is already gone by then); going out is an
        // instant swap back. The design's "slides away" loses to the budget.
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)),
                removal: .identity
            )
        )
    }

    private func option(
        _ scope: WatchWorkoutViewModel.RestAdjustmentScope,
        title: LocalizedStringKey
    ) -> some View {
        let isSelected = selection == scope
        return Button {
            onSelect(scope)
        } label: {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    // Never white on tint — see the contrast rule in CLAUDE.md.
                    isSelected ? OnyxWatch.Colors.textOnTint : OnyxWatch.Colors.chipText
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule().fill(OnyxWatch.Colors.tint)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension View {
    /// Cross-fades this row with the adjustment footer **in the row's own
    /// slot**. Apply it to the Minimize/Skip row: while the Crown is turning,
    /// the buttons fade out and the ruler + `old → new` line take their place.
    ///
    /// The row stays the layout element — an overlay's base view "continues to
    /// provide the layout characteristics for the resulting combined view" — so
    /// the slot keeps the buttons' height and nothing on screen moves.
    ///
    /// This screen has no vertical slack to give the footer a slot of its own:
    /// with the metrics row, the caption, 44pt digits and the buttons, a 46 mm
    /// watch leaves ≈29 pt in each `Spacer`. Two earlier attempts are recorded
    /// in `docs/watch-rest-timer-ui.md` — reserving fixed-height slots (pushed
    /// the content past the safe area at both ends) and hanging the footer
    /// below the digits via an alignment guide (drew it straight over the
    /// buttons). Borrowing the button row is what actually fits.
    ///
    /// The buttons stop hit-testing while they are invisible, so a tap during a
    /// rotation can't skip the rest by accident.
    func restAdjustmentFooter(_ footer: RestAdjustmentFooter, isAdjusting: Bool) -> some View {
        opacity(isAdjusting ? 0 : 1)
            .allowsHitTesting(!isAdjusting)
            .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
            .overlay { footer }
    }
}
