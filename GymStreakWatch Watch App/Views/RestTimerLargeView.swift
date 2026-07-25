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
    let onSkip: () -> Void
    let onMinimize: () -> Void

    @State private var lastHapticTriggerTime: Int? = nil
    @State private var pulse = false
    @State private var backgroundPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            backgroundProgressLayer
            runningContent
        }
        // No opaque background out here: the screen is covered by the progress
        // surface below, which SHRINKS into the pill during the morph and
        // reveals the workout underneath as it goes.
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
        VStack(spacing: 6) {
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
            VStack(spacing: 6) {
                Text("Rest")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.5)

                // The shared countdown. Matched on POSITION only: the two states
                // use different fonts, and matchedGeometryEffect interpolates
                // position and size but never font size — matching the frame
                // would squeeze a 44pt string into the pill's box (and vice
                // versa) and make the digits re-lay-out on every animation step.
                // `.fixedSize()` keeps the intrinsic size whatever the morph
                // proposes; `.contentTransition(.identity)` keeps a digit change
                // landing mid-morph from being animated by the spring.
                Text(formattedTime)
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(shouldPulse ? .red : .white)
                    .shadow(color: (shouldPulse ? Color.red : Color.white).opacity(0.5), radius: shouldPulse ? 8 : 4)
                    .scaleEffect(shouldPulse ? (pulse ? 1.15 : 1.0) : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: shouldPulse)
                    .fixedSize()
                    .contentTransition(.identity)
                    .matchedGeometryEffect(
                        id: WatchRestTimerMorph.digitsID,
                        in: namespace,
                        properties: .position,
                        anchor: .center
                    )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest timer, \(formattedTime) remaining")

            Spacer()

            // MARK: - Bottom Row: Actions
            HStack(spacing: 10) {
                Button(action: onMinimize) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(2)
                }
                .tint(.gray)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.footnote.weight(.semibold))
                }
                .tint(OnyxWatch.Colors.warning)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .opacity(state == .running ? 1 : 0)
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
}
