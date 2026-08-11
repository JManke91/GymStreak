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

/// "REST", the Crown hint in the first seconds of a rest, or the `+15 s` badge
/// while adjusting.
///
/// The caption is always the layout element — the other two are drawn over it,
/// so they may be wider and taller without moving anything below. That is the
/// whole reason this slot carries all three: it is the only place on this screen
/// where something can appear for free (see `docs/watch-rest-timer-ui.md`,
/// "The vertical budget"), and "REST" is the one line that says nothing the
/// countdown below it has not already said.
struct RestAdjustmentCaption: View {
    let isAdjusting: Bool
    let delta: TimeInterval
    /// Advertise the Crown. Loses to `isAdjusting` — once the user is turning
    /// it, the delta is the more useful thing to show in the same slot.
    let showsCrownHint: Bool

    var body: some View {
        Text("Rest")
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.5)
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
