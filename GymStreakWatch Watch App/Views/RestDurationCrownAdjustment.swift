//
//  RestDurationCrownAdjustment.swift
//  GymStreakWatch Watch App
//
//  The Digital Crown half of adjusting a running rest: crown ownership, the
//  detent binding, the limit haptic, the animation throttle and the linger
//  before the editing chrome fades out.
//
//  Applied by RestTimerLargeView, which owns the presentation. The only state
//  the two share is `baseline` — the duration an adjustment started from, which
//  is `nil` whenever none is on screen.
//

import SwiftUI
import WatchKit

extension View {
    /// Lets the Digital Crown change the running rest's duration while this view
    /// is up. `isEnabled` must be false while a morph is in flight.
    func restDurationCrownAdjustment(
        isEnabled: Bool,
        baseline: Binding<TimeInterval?>,
        scope: Binding<WatchWorkoutViewModel.RestAdjustmentScope?>
    ) -> some View {
        modifier(
            RestDurationCrownAdjustment(isEnabled: isEnabled, baseline: baseline, scope: scope)
        )
    }
}

extension View {
    /// The VoiceOver path to the same adjustment. It reaches the countdown
    /// element rather than the Crown binding: it steps the duration directly
    /// and commits at once, with no editing chrome and no scope prompt — the
    /// spoken value is the feedback, and `onIdle` (which arms the prompt)
    /// covers Crown input only.
    func restDurationVoiceOverAdjustment(isEnabled: Bool) -> some View {
        modifier(RestDurationVoiceOverAdjustment(isEnabled: isEnabled))
    }
}

private struct RestDurationVoiceOverAdjustment: ViewModifier {
    @EnvironmentObject private var viewModel: WatchWorkoutViewModel

    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let step = WatchWorkoutViewModel.restDurationStep
            switch direction {
            case .increment: viewModel.adjustRestDuration(to: viewModel.restDuration + step)
            case .decrement: viewModel.adjustRestDuration(to: viewModel.restDuration - step)
            @unknown default: break
            }
            viewModel.commitRestDurationAdjustment()
        }
    }
}

struct RestDurationCrownAdjustment: ViewModifier {
    @EnvironmentObject private var viewModel: WatchWorkoutViewModel

    let isEnabled: Bool
    @Binding var baseline: TimeInterval?
    /// The scope prompt's state: `nil` means the row is not on screen, otherwise
    /// the option it currently shows as selected. Written here (arming and
    /// auto-dismissal), read and — on a tap — written by the large state.
    @Binding var scope: WatchWorkoutViewModel.RestAdjustmentScope?

    /// The detent-snapped value the Crown writes. Kept in step with
    /// `viewModel.restDuration` whenever no adjustment is in progress.
    @State private var crownDuration: Double = 0
    @FocusState private var isCrownFocused: Bool

    /// Fades the editing chrome back out a moment after rotation settles, then
    /// runs the scope prompt's whole life cycle. One task, so the two can never
    /// race or overlap.
    @State private var chromeLingerTask: Task<Void, Never>?
    /// Last time a digit change was committed inside an animated transaction.
    @State private var lastAnimatedCommit: Date = .distantPast
    /// One limit haptic per arrival at a bound, not one per detent.
    @State private var limitHapticPlayed = false
    /// The value `resyncCrownIfIdle()` last wrote into the binding, so its echo
    /// through `onChange` is not mistaken for a rotation.
    @State private var lastSeededCrownValue: Double?

    /// Raw detents arrive 5–10×/s at this sensitivity; animating every one of
    /// them reads as flicker, so `.numericText()` runs at most this often.
    private static let digitAnimationInterval: TimeInterval = 0.15
    /// How long the delta badge, tick track and old→new line stay up after the
    /// Crown stops turning. Kept short because the footer borrows the
    /// Minimize/Skip slot: this is also how long those buttons stay away.
    ///
    /// It doubles as the scope prompt's arming delay — the "~1 s after the last
    /// detent" of the design. Deliberately the *same* number: the editing chrome
    /// leaving and the scope row arriving are one hand-off, and the two states
    /// must never be on screen together (there is no vertical room for both).
    private static let chromeLinger: TimeInterval = 1.2

    func body(content: Content) -> some View {
        content
            // Crown ownership: while the large timer is up it covers the whole
            // display, so it owns the Crown; the minimized pill deliberately
            // does not, leaving the crown to the list underneath. `.focusable`
            // MUST come before `.digitalCrownRotation` or crown input silently
            // does nothing.
            .focusable(isEnabled)
            .focused($isCrownFocused)
            .digitalCrownRotation(
                detent: $crownDuration,
                from: WatchWorkoutViewModel.restDurationRange.lowerBound,
                through: WatchWorkoutViewModel.restDurationRange.upperBound,
                by: WatchWorkoutViewModel.restDurationStep,
                // Passed explicitly: Apple's overview page documents the default
                // as `.medium` and this overload's own page as `.high`. `by:` is
                // what makes the 5 s step; sensitivity only sets
                // rotation-per-detent.
                sensitivity: .medium,
                // `true` would wrap 10:00 back around to 0:05 instead of
                // clamping.
                isContinuous: false,
                // Plays the per-detent click for us — do not also play `.click`.
                isHapticFeedbackEnabled: true,
                onIdle: endAdjustment
            )
            .onChange(of: crownDuration) { _, newValue in applyCrownDuration(newValue) }
            .onChange(of: viewModel.restDuration) { _, _ in resyncCrownIfIdle() }
            .onChange(of: isEnabled) { _, enabled in
                resyncCrownIfIdle()
                isCrownFocused = enabled
                // Only when the rest itself is gone — NOT on the morph half of
                // `isEnabled`. Tearing the chrome down as a morph starts would
                // change this column's layout in the same frame the shared
                // digits begin interpolating; minimizing unmounts the large
                // state anyway, so the row cross-fades out with everything else.
                if !viewModel.canAdjustRestDuration { dismissScopePrompt() }
            }
            .onAppear {
                resyncCrownIfIdle()
                isCrownFocused = isEnabled
            }
            .onDisappear { chromeLingerTask?.cancel() }
    }

    private func applyCrownDuration(_ newValue: Double) {
        // Ignore the echo of our own seeding. Without this, a rest longer than
        // the Crown's maximum (the binding gets clamped into range on seed)
        // would silently shorten itself the moment the timer appeared.
        if lastSeededCrownValue == newValue {
            lastSeededCrownValue = nil
            return
        }
        guard isEnabled else { return }
        adjust(to: newValue.rounded())
    }

    private func adjust(to newDuration: TimeInterval) {
        // Clamped on this side too — deliberately, not redundantly: the view
        // model clamps what it stores, and the guard below needs the value it
        // WOULD store to decide whether anything changes at all.
        let clamped = newDuration.clamped(to: WatchWorkoutViewModel.restDurationRange)
        guard clamped != viewModel.restDuration else { return }

        if baseline == nil {
            // Cancels whatever stage the previous adjustment's tail was in — the
            // chrome linger, the prompt's arming delay, or its 3 s life. A
            // rotation while the row is up therefore RE-ARMS the one row rather
            // than stacking a second: it leaves now and comes back with the
            // fresh commit preselected.
            chromeLingerTask?.cancel()
            if scope != nil {
                withAnimation(RestScopeRow.spring) { scope = nil }
            }
            baseline = viewModel.restDuration
        }
        playLimitHapticIfNeeded(for: clamped)

        // Throttle the ANIMATED commits only — the value itself is always
        // applied immediately, so the model never lags the Crown.
        let now = Date()
        if now.timeIntervalSince(lastAnimatedCommit) >= Self.digitAnimationInterval {
            lastAnimatedCommit = now
            withAnimation(.snappy(duration: RestAdjustmentChrome.crossfade)) {
                viewModel.adjustRestDuration(to: clamped)
            }
        } else {
            viewModel.adjustRestDuration(to: clamped)
        }
    }

    /// Fires when Crown rotation settles: makes the change durable, then runs
    /// the tail — editing chrome out, scope prompt in, scope prompt out.
    private func endAdjustment() {
        guard baseline != nil else { return }
        viewModel.commitRestDurationAdjustment()

        chromeLingerTask?.cancel()
        chromeLingerTask = Task {
            try? await Task.sleep(for: .seconds(Self.chromeLinger))
            guard !Task.isCancelled else { return }
            // One transaction: the badge and footer hand their space straight to
            // the scope row. `.allSets` is preselected because that is exactly
            // what the commit above just wrote.
            withAnimation(RestScopeRow.spring) {
                baseline = nil
                scope = .allSets
            }
            // Covers the VoiceOver path, which changes the duration without
            // going through the Crown binding. Same seeding path as everywhere
            // else, so the echo guard and the clamp both apply.
            resyncCrownIfIdle()

            try? await Task.sleep(for: .seconds(RestScopeRow.life))
            guard !Task.isCancelled else { return }
            withAnimation(RestScopeRow.spring) { scope = nil }
        }
    }

    /// Tears the whole tail down at once. Cancelling the task alone would strand
    /// whichever stage it had not reached yet — a half-faded editing chrome or a
    /// row that never dismisses.
    private func dismissScopePrompt() {
        chromeLingerTask?.cancel()
        guard scope != nil || baseline != nil else { return }
        withAnimation(RestScopeRow.spring) {
            scope = nil
            baseline = nil
        }
    }

    /// There is no built-in limit haptic — the bound has to be detected and
    /// played manually, once per arrival rather than once per detent.
    private func playLimitHapticIfNeeded(for duration: TimeInterval) {
        let range = WatchWorkoutViewModel.restDurationRange
        if duration <= range.lowerBound {
            if !limitHapticPlayed { WKInterfaceDevice.current().play(.directionDown) }
            limitHapticPlayed = true
        } else if duration >= range.upperBound {
            if !limitHapticPlayed { WKInterfaceDevice.current().play(.directionUp) }
            limitHapticPlayed = true
        } else {
            limitHapticPlayed = false
        }
    }

    /// Keeps the Crown's detent value on the running rest's duration whenever no
    /// adjustment is in flight — a new rest starting, or one the Crown was not
    /// allowed to write while a morph ran.
    private func resyncCrownIfIdle() {
        guard baseline == nil else { return }
        let duration = viewModel.restDuration
        guard duration > 0 else { return }

        let seeded = duration.clamped(to: WatchWorkoutViewModel.restDurationRange)
        guard crownDuration != seeded else { return }
        lastSeededCrownValue = seeded
        crownDuration = seeded
    }
}
