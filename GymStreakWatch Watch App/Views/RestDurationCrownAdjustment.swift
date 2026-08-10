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
        baseline: Binding<TimeInterval?>
    ) -> some View {
        modifier(RestDurationCrownAdjustment(isEnabled: isEnabled, baseline: baseline))
    }
}

struct RestDurationCrownAdjustment: ViewModifier {
    @EnvironmentObject private var viewModel: WatchWorkoutViewModel

    let isEnabled: Bool
    @Binding var baseline: TimeInterval?

    /// The detent-snapped value the Crown writes. Kept in step with
    /// `viewModel.restDuration` whenever no adjustment is in progress.
    @State private var crownDuration: Double = 0
    @FocusState private var isCrownFocused: Bool

    /// Fades the editing chrome back out a moment after rotation settles.
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
            chromeLingerTask?.cancel()
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

    /// Fires when Crown rotation settles: makes the change durable and starts
    /// the countdown back to the idle presentation.
    private func endAdjustment() {
        guard baseline != nil else { return }
        viewModel.commitRestDurationAdjustment()

        chromeLingerTask?.cancel()
        chromeLingerTask = Task {
            try? await Task.sleep(for: .seconds(Self.chromeLinger))
            guard !Task.isCancelled else { return }
            baseline = nil
            // Covers the VoiceOver path, which changes the duration without
            // going through the Crown binding. Same seeding path as everywhere
            // else, so the echo guard and the clamp both apply.
            resyncCrownIfIdle()
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
