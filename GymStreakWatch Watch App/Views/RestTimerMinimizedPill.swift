//
//  RestTimerMinimizedPill.swift
//  GymStreakWatch Watch App
//
//  The MINIMIZED half of the rest timer. Mounted only by
//  WorkoutRestTimerOverlay, which owns the morph namespace shared with
//  RestTimerLargeView.
//
//  Two gestures: TAP expands back to the large timer, LONG PRESS grows the pill
//  into the inline ± stepper (`RestPillStepper`) and takes the Digital Crown for
//  as long as it is open. Long press used to skip the rest — see
//  `docs/watch-rest-timer-ui.md` for why that was given up.
//

import SwiftUI
import WatchKit

struct RestTimerMinimizedPill: View {
    @EnvironmentObject private var viewModel: WatchWorkoutViewModel

    let timeRemaining: Double
    let totalDuration: Double
    /// Shared with the large timer so the pill's surface and digits morph out of
    /// (and back into) it — see `WatchRestTimerMorph`.
    let namespace: Namespace.ID
    /// Who owns the Digital Crown right now. The pill claims it only as
    /// `.pillStepper`, i.e. only while its stepper is open, so the exercise list
    /// underneath keeps Crown scrolling the rest of the time.
    let crownOwner: WatchRestCrownOwner
    /// Whether the pill is grown into the stepper. Owned by `ActiveWorkoutView`
    /// (the workout screens fade their top-trailing label while it is true) and
    /// toggled here.
    @Binding var isStepperOpen: Bool
    let onExpand: () -> Void

    @State private var pulse = false

    /// The detent-snapped value the Crown writes while the stepper is open. Kept
    /// in step with `viewModel.restDuration` whenever it is closed, and re-seeded
    /// after every ± tap so a rotation right after a tap continues from the
    /// tapped value instead of jumping back.
    @State private var crownDuration: Double = 0
    @FocusState private var isCrownFocused: Bool
    /// Collapses the stepper `WatchRestPillStepper.life` after the last input.
    @State private var collapseTask: Task<Void, Never>?
    /// One limit haptic per arrival at a bound, not one per tap/detent.
    @State private var limitHapticPlayed = false
    /// The value the crown binding was last seeded with, so its echo through
    /// `onChange` is not mistaken for a rotation.
    @State private var lastSeededCrownValue: Double?

    let totalWidth: CGFloat = 30

    var body: some View {
        pillChrome
            // The pill hands its whole appearance to the stepper while that is
            // open. Opacity, not removal: the surface and the digits carry the
            // morph's matchedGeometryEffect ids and must stay mounted (and keep
            // reporting geometry) so a tap-to-expand still morphs from the right
            // place. Opacity does not affect layout, so nothing moves.
            .opacity(isStepperOpen ? 0 : 1)
            .overlay(alignment: .trailing) {
                // Built only while open — this body re-evaluates once a second
                // from the countdown alone.
                if isStepperOpen {
                    RestPillStepper(duration: viewModel.restDuration, onAdjust: adjust(by:))
                        .transition(
                            .scale(scale: 0.35, anchor: .trailing).combined(with: .opacity)
                        )
                }
            }
            // Invisible margin AROUND the drawn pill, inside the gesture area: the
            // visible pill is only ~22pt tall, far below a comfortable watch touch
            // target, so taps next to the digits used to miss and only the chevron
            // end felt reliable. Drawing is unchanged — this only grows the region
            // `contentShape` hands to the two gestures below.
            .padding(Self.touchInset)
            .contentShape(Rectangle())
            .onTapGesture {
                // While the stepper is open, the pill's own hit region sits
                // under the stepper's right half and part of the duration
                // readout — which is not a Button — so a tap landing here is far
                // more likely to be a near-miss of "+15" than a request to
                // expand. It buys another 3 s instead; expanding is one tap away
                // again the moment the stepper collapses.
                guard !isStepperOpen else {
                    scheduleCollapse()
                    return
                }
                WKInterfaceDevice.current().play(.click)
                onExpand()
            }
            .onLongPressGesture(minimumDuration: 0.5) { openStepper() }
            // Crown ownership. `.focusable` MUST precede `.digitalCrownRotation`
            // or crown input silently does nothing. Exactly one view is ever
            // focusable because both candidates key off the same owner value.
            .focusable(crownOwner == .pillStepper)
            .focused($isCrownFocused)
            .digitalCrownRotation(
                detent: $crownDuration,
                from: WatchWorkoutViewModel.restDurationRange.lowerBound,
                through: WatchWorkoutViewModel.restDurationRange.upperBound,
                by: WatchWorkoutViewModel.restDurationStep,
                // Passed explicitly: Apple's overview page documents the default
                // as `.medium` and this overload's own page as `.high`.
                sensitivity: .medium,
                // `true` would wrap 10:00 back around to 0:05 instead of clamping.
                isContinuous: false,
                // Plays the per-detent click for us — do not also play `.click`.
                isHapticFeedbackEnabled: true,
                onIdle: scheduleCollapse
            )
            .onChange(of: crownDuration) { _, newValue in applyCrownDuration(newValue) }
            .onChange(of: viewModel.restDuration) { _, _ in resyncCrownIfClosed() }
            // There is no focus-restoration stack on watchOS: ownership is handed
            // back by flipping this ourselves, which is also what makes the
            // exercise list scroll with the Crown again the moment we collapse.
            .onChange(of: crownOwner) { _, owner in isCrownFocused = owner == .pillStepper }
            .onChange(of: viewModel.canAdjustRestDuration) { _, canAdjust in
                if !canAdjust { collapse() }
            }
            .onAppear {
                resyncCrownIfClosed()
                isCrownFocused = crownOwner == .pillStepper
            }
            // Expanding or skipping right after a change unmounts the pill before
            // its collapse fires, so the buffered write is flushed here too. It
            // is a no-op when there is nothing pending.
            .onDisappear {
                collapseTask?.cancel()
                viewModel.commitRestDurationAdjustment()
            }
    }

    /// Transparent touch margin on every side of the drawn pill. Whoever
    /// positions the pill must compensate for it — see `WorkoutRestTimerOverlay`.
    static let touchInset: CGFloat = 8

    // MARK: - Chrome

    private var pillChrome: some View {
        HStack(spacing: 6) {

            ZStack {

                // --- BACKGROUND CAPSULE ---
                Capsule()
                    .fill(.black.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.10), lineWidth: 0.8)
                    )

                // --- SMOOTH REMAINING BAR ---
                Capsule()
                    .fill(gradientFill)
                    .scaleEffect(x: smoothProgress, y: 1, anchor: .leading)
                    .animation(.easeInOut(duration: 0.35), value: smoothProgress)
                    // GPU-MASK to prevent any pixel bleeding
                    .mask(Capsule())

                // --- TIME LABEL ---
                // The shared countdown, matched on POSITION only — see the
                // large timer for why the frame must never be matched.
                Text(formattedTime)
                    .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .shadow(radius: 0.5)
                    .fixedSize()
                    .contentTransition(.identity)
                    .matchedGeometryEffect(
                        id: WatchRestTimerMorph.digitsID,
                        in: namespace,
                        properties: .position,
                        anchor: .center
                    )
            }
            .frame(width: totalWidth, height: 15)
            .scaleEffect(pulse ? 1.06 : 1.00)
            .animation(pulseAnimation, value: pulse)
            .onChange(of: timeRemaining) {
                if timeRemaining <= 3 { pulse = true }
            }

            // Chevron icon
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }

        // --- CONTAINER CARD STYLE ---
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(morphSurface)
    }

    // MARK: - Inline Stepper

    /// Long press: grow into the stepper and take the Crown. A repeat press
    /// while it is already open just restarts the collapse timer.
    private func openStepper() {
        guard !isStepperOpen else {
            scheduleCollapse()
            return
        }
        guard viewModel.canAdjustRestDuration else { return }

        WKInterfaceDevice.current().play(.start)
        seedCrown(to: viewModel.restDuration)
        withAnimation(WatchRestPillStepper.spring) { isStepperOpen = true }
        scheduleCollapse()
    }

    /// A ± tap. The Crown keeps working in parallel, so both paths go through
    /// the same setter and both restart the collapse timer.
    private func adjust(by delta: TimeInterval) {
        if setDuration(viewModel.restDuration + delta) {
            WKInterfaceDevice.current().play(.click)
        }
        seedCrown(to: viewModel.restDuration)
        scheduleCollapse()
    }

    private func applyCrownDuration(_ newValue: Double) {
        // Ignore the echo of our own seeding, or a rest longer than the Crown's
        // maximum would silently shorten itself the moment we seeded it.
        if lastSeededCrownValue == newValue {
            lastSeededCrownValue = nil
            return
        }
        guard crownOwner == .pillStepper else { return }
        setDuration(newValue.rounded())
        // `onIdle` only fires once rotation settles; a rotation longer than the
        // stepper's life would otherwise collapse it mid-turn.
        scheduleCollapse()
    }

    /// The one place either input path changes the duration. Returns whether the
    /// value actually moved, so a tap at the bound plays the limit haptic
    /// instead of the click.
    @discardableResult
    private func setDuration(_ duration: TimeInterval) -> Bool {
        let clamped = duration.clamped(to: WatchWorkoutViewModel.restDurationRange)
        RestLimitHaptic.play(reaching: clamped, hasPlayed: &limitHapticPlayed)
        guard clamped != viewModel.restDuration else { return false }

        // No animated digit transition here, and therefore no throttle: the
        // stepper's label is a 14pt string, and at 5–10 detents/s a
        // glyph-replacing transition on it would read as flicker (the large
        // timer's `.numericText()` needs a 150 ms throttle for exactly that).
        viewModel.adjustRestDuration(to: clamped)
        return true
    }

    /// Deliberately does NOT gate on `isStepperOpen`: `openStepper()` schedules
    /// the first collapse in the same call that opens the stepper, and a
    /// `@Binding` read back inside the write's own transaction is not a contract
    /// worth betting the auto-collapse on. A task started while the stepper is
    /// closed is harmless — `collapse()` checks the flag when it fires.
    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: .seconds(WatchRestPillStepper.life))
            guard !Task.isCancelled else { return }
            collapse()
        }
    }

    /// Shrinks back to the plain countdown and makes the change durable. The
    /// write itself is ticket 01's — `commitRestDurationAdjustment()` writes to
    /// every set of the owning exercise(s), the whole group during a superset
    /// round, and checkpoints it.
    private func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        guard isStepperOpen else { return }

        withAnimation(WatchRestPillStepper.spring) { isStepperOpen = false }
        viewModel.commitRestDurationAdjustment()
        limitHapticPlayed = false
    }

    /// Keeps the Crown's detent value on the running rest's duration whenever the
    /// stepper is closed — a new rest starting, or one adjusted from the large
    /// timer while this was down.
    private func resyncCrownIfClosed() {
        guard !isStepperOpen, viewModel.restDuration > 0 else { return }
        seedCrown(to: viewModel.restDuration)
    }

    private func seedCrown(to duration: TimeInterval) {
        let seeded = duration.clamped(to: WatchWorkoutViewModel.restDurationRange)
        guard crownDuration != seeded else { return }
        lastSeededCrownValue = seeded
        crownDuration = seeded
    }

    // MARK: - Shared Surface

    /// The small half of the shared progress surface: the pill's card, drawn as
    /// the *same* continuous rounded rectangle the large panel uses so only the
    /// frame has to interpolate.
    ///
    /// As a `.background` it takes the pill's own frame, and it is free to draw
    /// far outside that box while the morph drives it to the large panel's
    /// frame. It carries no hard frame of its own — the matched effect owns the
    /// size proposal.
    private var morphSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WatchRestTimerMorph.surfaceCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 4, y: -1)

            RoundedRectangle(cornerRadius: WatchRestTimerMorph.surfaceCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .matchedGeometryEffect(id: WatchRestTimerMorph.surfaceID, in: namespace)
    }

    // MARK: - Computed Properties

    private var smoothProgress: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(timeRemaining / totalDuration)
    }

    private var formattedTime: String {
        let seconds = Int(timeRemaining)
        return String(format: "%02d", seconds)
    }

    private var gradientFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.yellow.opacity(0.90),
                Color.yellow.opacity(0.55)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // Pulse effect for the last 3 seconds
    private var pulseAnimation: Animation {
        .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    }
}
