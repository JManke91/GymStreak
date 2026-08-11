//
//  RestTimerLargeView.swift
//  GymStreakWatch Watch App
//
//  The LARGE half of the rest timer. Mounted only by WorkoutRestTimerOverlay,
//  which owns the morph namespace shared with RestTimerMinimizedPill.
//

import SwiftUI
import WatchKit

struct RestTimerLargeView: View {
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    let timeRemaining: TimeInterval
    let totalDuration: TimeInterval
    let formattedTime: String
    let state: WatchWorkoutViewModel.RestTimerState
    /// Shared with the minimized pill so the progress surface and the digits
    /// morph between the two states — see `WatchRestTimerMorph`.
    let namespace: Namespace.ID
    /// False while the large↔pill morph runs. Gates the digits'
    /// `.numericText()` transition — see `WorkoutRestTimerOverlay`.
    let isMorphSettled: Bool
    /// Who owns the Digital Crown. This state adjusts only as `.largeTimer`; the
    /// overlay derives the value, so it can never be focusable at the same time
    /// as the pill's inline stepper.
    let crownOwner: WatchRestCrownOwner
    let onSkip: () -> Void
    let onMinimize: () -> Void

    /// Case-size tier. This screen has no scroll and no slack, so every fixed
    /// point value on it (countdown, paddings, the two action buttons) has to
    /// come down on a 40 mm watch — see `WorkoutScreenMetrics`.
    private let metrics = WorkoutScreenMetrics.current

    @State private var lastHapticTriggerTime: Int? = nil
    @State private var pulse = false
    @State private var backgroundPulse: CGFloat = 1.0

    /// The duration the current adjustment started from — and the flag for
    /// "an adjustment is on screen". `nil` means the idle presentation.
    /// Owned here because the chrome reads it; everything else about the Crown
    /// lives in `RestDurationCrownAdjustment`.
    @State private var adjustmentBaseline: TimeInterval?

    /// The scope prompt: `nil` while the row is off screen, otherwise the option
    /// it shows as selected. Armed and auto-dismissed by the same modifier.
    @State private var adjustmentScope: WatchWorkoutViewModel.RestAdjustmentScope?

    var body: some View {
        ZStack {
            backgroundProgressLayer
            runningContent
        }
        // No opaque background out here: the screen is covered by the progress
        // surface below, which SHRINKS into the pill during the morph and
        // reveals the workout underneath as it goes.
        .restDurationCrownAdjustment(
            isEnabled: canAdjust,
            baseline: $adjustmentBaseline,
            scope: $adjustmentScope
        )
        .onAppear { pulse = true }
        .onChange(of: shouldPulse) { isPulsing in
            if isPulsing {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    backgroundPulse = 1.03
                    pulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    backgroundPulse = 1.0
                    pulse = false
                }
            }
        }
        .onChange(of: timeRemaining) { newTime in
            guard state == .running else { return }

            let currentSecond = Int(newTime.rounded(.up))

            // Play notification haptic at 3, 2, 1 seconds
            if [3, 2, 1].contains(currentSecond) && currentSecond != lastHapticTriggerTime {
                WKInterfaceDevice.current().play(.notification)
                lastHapticTriggerTime = currentSecond
            }

            // Play strong success haptic at 0
            if newTime <= 0.05 && lastHapticTriggerTime != 0 {
                WKInterfaceDevice.current().play(.success)
                lastHapticTriggerTime = 0
            }

            // Reset haptic tracking when above 3 seconds
            if currentSecond > 3 && lastHapticTriggerTime != nil {
                lastHapticTriggerTime = nil
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.35), value: state)
    }

    private var progressColor: Color {
        let normalizedProgress = 1.0 - progress
        let hue: Double = 0.55 - (normalizedProgress * 0.25)
        return Color(hue: hue, saturation: 0.8, brightness: 0.8)
    }

    // MARK: ─── Gradient + Glow Background
    /// The large half of the shared progress surface: an opaque, screen-filling
    /// panel whose gradient drains bottom-up with the remaining time.
    ///
    /// It is drawn as the *same* continuous rounded rectangle the pill uses, and
    /// carries the shared `matchedGeometryEffect` id with **no hard frame between
    /// the effect and the shape** — the effect has to own the size proposal, or
    /// the morph degrades into a move plus a cross-fade.
    private var backgroundProgressLayer: some View {
        ZStack {
            OnyxWatch.Colors.background

            LinearGradient(
                gradient: Gradient(colors: [progressColor.opacity(0.8), .black]),
                startPoint: .bottom,
                endPoint: .top
            )
            .scaleEffect(x: 1, y: progress, anchor: .bottom)
            .animation(.linear(duration: 0.5), value: progress)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: WatchRestTimerMorph.surfaceCornerRadius,
                style: .continuous
            )
        )
        .matchedGeometryEffect(id: WatchRestTimerMorph.surfaceID, in: namespace)
        .scaleEffect(backgroundPulse)
        .animation(.easeInOut(duration: 0.6), value: backgroundPulse)
        .ignoresSafeArea()
    }

    // MARK: ─── Running UI
    private var runningContent: some View {
        VStack(spacing: metrics.restStackSpacing) {
            // MARK: - Top Row: Secondary Metrics
            HStack {
                if let heartRate = viewModel.heartRate, let calories = viewModel.activeCalories {
                    WorkoutMetricsView(heartRate: heartRate, calories: calories, size: .small)
                }

                Spacer()

                if let elapsedTime = viewModel.elapsedTimeString {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(elapsedTime)
                            .font(.system(.caption, design: .rounded).weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Total workout time \(elapsedTime)")
                }
            }
            .padding(.horizontal, 6)

            Spacer()

            // MARK: - Center: Primary Timer (Label + Countdown)
            VStack(spacing: metrics.restCenterSpacing) {
                // The caption yields its slot to the scope row (see "The
                // vertical budget"). COLLAPSED, not removed: a removal
                // transition keeps its slot until it finishes, so an `if` would
                // put caption and row in the column together for the spring.
                RestAdjustmentCaption(isAdjusting: isAdjusting, delta: adjustmentDelta)
                    .frame(height: captionHeight)
                    .opacity(isScopePromptUp ? 0 : 1)
                    // Its own fast crossfade, not the row's spring: a zero-height
                    // frame does not clip (and must not — the delta badge
                    // overflows it by design), so a slow fade would ghost.
                    .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isScopePromptUp)

                // The shared countdown. Matched on POSITION only: the two states
                // use different fonts, and matchedGeometryEffect interpolates
                // position and size but never font size — matching the frame
                // would squeeze a 44pt string into the pill's box (and vice
                // versa) and make the digits re-lay-out on every animation step.
                // `.fixedSize()` keeps the intrinsic size whatever the morph
                // proposes; `.contentTransition(.identity)` keeps a digit change
                // landing mid-morph from being animated by the spring.
                Text(formattedTime)
                    .font(.system(size: metrics.restCountdownSize, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(digitColor)
                    .shadow(color: digitColor.opacity(0.5), radius: shouldPulse || isAdjusting ? 8 : 4)
                    .scaleEffect(shouldPulse ? (pulse ? 1.15 : 1.0) : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: shouldPulse)
                    .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
                    .fixedSize()
                    // `.numericText()` only once the morph has settled: a Text
                    // has one active content transition, and a glyph-replacing
                    // one would override the `.identity` the shared digits need
                    // while they are mid-matchedGeometry interpolation.
                    .contentTransition(isMorphSettled ? .numericText() : .identity)
                    .matchedGeometryEffect(
                        id: WatchRestTimerMorph.digitsID,
                        in: namespace,
                        properties: .position,
                        anchor: .center
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest timer, \(formattedTime) remaining")
            .accessibilityValue(Text("Rest duration \(RestAdjustmentChrome.durationText(totalDuration))"))
            .accessibilityHint(Text("Turn the Digital Crown to change the rest duration"))
            .restDurationVoiceOverAdjustment(isEnabled: canAdjust)

            // Outside the countdown's combined accessibility element: these are
            // two real buttons, not part of the timer's spoken value.
            if let adjustmentScope {
                RestScopeRow(selection: adjustmentScope, onSelect: selectScope)
            }

            Spacer()

            // MARK: - Bottom Row: Actions, or the adjustment footer
            //
            // The two share this slot: there is no vertical room on this screen
            // for a slot of the footer's own, and the buttons are the one thing
            // the user is definitely not reaching for while turning the Crown.
            HStack(spacing: 10) {
                Button(action: onMinimize) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: metrics.restMinimizeIconSize, weight: .semibold))
                        .padding(2)
                }
                .tint(.gray)

                Button(action: onSkip) {
                    // German "Überspringen" is more than twice the length of
                    // "Skip" and only has half the row to live in. Without this
                    // it wrapped to two lines, which grew the row and pushed it
                    // into the adjustment footer drawn over the same slot.
                    Text("Skip")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .tint(OnyxWatch.Colors.warning)
            }
            .buttonBorderShape(.capsule)
            .restAdjustmentFooter(
                RestAdjustmentFooter(
                    isAdjusting: isAdjusting,
                    baseline: adjustmentBaseline ?? totalDuration,
                    current: totalDuration,
                    step: WatchWorkoutViewModel.restDurationStep
                ),
                isAdjusting: isAdjusting
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, metrics.restVerticalPadding)
        .opacity(state == .running ? 1 : 0)
    }

    // MARK: ─── Crown Handling

    private var isAdjusting: Bool { adjustmentBaseline != nil }

    private var isScopePromptUp: Bool { adjustmentScope != nil }

    /// `nil` is the caption's intrinsic height; `0` hands its slot to the row.
    private var captionHeight: CGFloat? { isScopePromptUp ? 0 : nil }

    private var adjustmentDelta: TimeInterval {
        guard let baseline = adjustmentBaseline else { return 0 }
        return totalDuration - baseline
    }

    /// Answers the scope prompt. The running countdown is untouched either way —
    /// only what the *following* sets rest for changes.
    private func selectScope(_ scope: WatchWorkoutViewModel.RestAdjustmentScope) {
        withAnimation(RestScopeRow.spring) { adjustmentScope = scope }
        viewModel.applyRestAdjustmentScope(scope)
        WKInterfaceDevice.current().play(.click)
    }

    /// The Crown is inert unless the rest is genuinely adjustable AND this state
    /// owns the Crown (which the overlay withholds while a morph is in flight).
    private var canAdjust: Bool {
        viewModel.canAdjustRestDuration && crownOwner == .largeTimer && state == .running
    }

    // MARK: ─── Computed Properties

    private var progress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(timeRemaining / totalDuration)
    }

    /// Pulse for last 3 seconds
    private var shouldPulse: Bool {
        timeRemaining <= 3 && state == .running
    }

    /// The digits' editing treatment: while the Crown is changing them they
    /// take the delta badge's tint, so the number itself reads as the thing
    /// being edited rather than a countdown that happens to be moving.
    ///
    /// A colour change only — the digits carry `matchedGeometryEffect` and
    /// `.fixedSize()`, so nothing here may touch their size or position. The
    /// last-3-seconds red always wins: urgency outranks editing.
    private var digitColor: Color {
        if shouldPulse { return .red }
        return isAdjusting ? OnyxWatch.Colors.tint : .white
    }
}
