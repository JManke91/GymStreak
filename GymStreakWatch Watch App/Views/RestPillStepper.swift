//
//  RestPillStepper.swift
//  GymStreakWatch Watch App
//
//  The minimized rest pill grown into an inline stepper — `−15 · 1:45 · +15`.
//  Presentation only: RestTimerMinimizedPill owns the long press that opens it,
//  the Digital Crown while it is open, and the 3 s collapse.
//
//  It is drawn as an OVERLAY on the pill's card, anchored to the card's trailing
//  edge and extending leftward. That is what keeps the promise of "grows in
//  place": an overlay takes no layout space of its own, so the pill's box, the
//  overlay's positioning constants and therefore the drawn pill's height and
//  vertical position are all untouched by opening it. See
//  `docs/watch-rest-timer-ui.md`.
//

import SwiftUI

enum WatchRestPillStepper {
    /// One tap of − / +. Deliberately coarser than the Crown's 5 s detent: a tap
    /// is a decision ("this rest is too short"), a detent is a nudge, and the
    /// pill has room for two targets, not twelve.
    static let tapStep: TimeInterval = 15

    /// How long the stepper stays open with no input. Restarted by every ± tap
    /// and every Crown detent — `onIdle` covers Crown idleness only.
    static let life: TimeInterval = 3

    /// Growing and shrinking.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    /// Hit side of each ± half.
    ///
    /// The ticket asked for ≥ 44 pt, which is the **iOS** figure; this project's
    /// own watch design handoff (§6, and `ChevronCircleStyle` on these same
    /// screens) puts the watchOS floor at 24 pt. 40 pt sits comfortably above
    /// that floor while leaving the grown pill inside the display on a 40 mm
    /// case — 44 pt on both halves would not fit there next to the duration.
    /// The region is a `contentShape`, so it does not depend on glyph size, and
    /// it overflows the drawn card vertically rather than making it taller.
    static let hitSide: CGFloat = 40
}

/// `−15 · 1:45 · +15` in the pill's own card style.
///
/// The card is the layout element (it takes the pill card's height from the
/// overlay's proposal and this view's fixed width), and the button row is drawn
/// over it — so the ± hit regions can be taller than the card without changing
/// what is drawn.
struct RestPillStepper: View {
    /// The rest duration being dialed in — not the remaining time. The pill's
    /// own countdown digits are hidden while this is up.
    let duration: TimeInterval
    /// Signed delta in seconds. Clamping, haptics and the collapse timer are the
    /// pill's job.
    let onAdjust: (TimeInterval) -> Void

    private let metrics = WorkoutScreenMetrics.current

    private var range: ClosedRange<TimeInterval> { WatchWorkoutViewModel.restDurationRange }

    var body: some View {
        card
            .frame(width: metrics.restPillStepperWidth)
            .overlay {
                HStack(spacing: 0) {
                    // The glyph label is derived from the step so the two cannot
                    // drift; the accessibility labels below spell out the same
                    // 15 s and DO have to be updated by hand if it ever changes
                    // (they are catalog keys — see docs/watch-localization.md).
                    stepHalf(
                        by: -WatchRestPillStepper.tapStep,
                        label: "−\(Int(WatchRestPillStepper.tapStep))",
                        accessibilityLabel: "Decrease rest by 15 seconds",
                        isAtLimit: duration <= range.lowerBound
                    )

                    Text(RestAdjustmentChrome.durationText(duration))
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(OnyxWatch.Colors.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Rest duration \(RestAdjustmentChrome.durationText(duration))"))

                    stepHalf(
                        by: WatchRestPillStepper.tapStep,
                        label: "+\(Int(WatchRestPillStepper.tapStep))",
                        accessibilityLabel: "Increase rest by 15 seconds",
                        isAtLimit: duration >= range.upperBound
                    )
                }
            }
    }

    /// One tappable half. Dimmed but still tappable at the bound — the tap plays
    /// the limit haptic, which says more than a dead button does.
    private func stepHalf(
        by delta: TimeInterval,
        label: String,
        accessibilityLabel: LocalizedStringKey,
        isAtLimit: Bool
    ) -> some View {
        Button {
            onAdjust(delta)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
                .opacity(isAtLimit ? 0.35 : 1)
                .frame(width: WatchRestPillStepper.hitSide, height: WatchRestPillStepper.hitSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// The pill's card, widened. Same continuous rounded rectangle so the grown
    /// state reads as the same object — with the tint hairline the large timer
    /// also uses to say "this number is being edited".
    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WatchRestTimerMorph.surfaceCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 4, y: -1)

            RoundedRectangle(cornerRadius: WatchRestTimerMorph.surfaceCornerRadius, style: .continuous)
                .stroke(OnyxWatch.Colors.tint.opacity(0.4), lineWidth: 1)
        }
    }
}
