//
//  RestTimerMinimizedPill.swift
//  GymStreakWatch Watch App
//
//  The MINIMIZED half of the rest timer. Mounted only by
//  WorkoutRestTimerOverlay, which owns the morph namespace shared with
//  RestTimerLargeView.
//

import SwiftUI
import WatchKit

struct RestTimerMinimizedPill: View {
    let timeRemaining: Double
    let totalDuration: Double
    /// Shared with the large timer so the pill's surface and digits morph out of
    /// (and back into) it — see `WatchRestTimerMorph`.
    let namespace: Namespace.ID
    let onExpand: () -> Void
    let onSkip: () -> Void

    @State private var pulse = false

    let totalWidth: CGFloat = 30

    var body: some View {
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
            .onChange(of: timeRemaining) { _ in
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
        // Invisible margin AROUND the drawn pill, inside the gesture area: the
        // visible pill is only ~22pt tall, far below a comfortable watch touch
        // target, so taps next to the digits used to miss and only the chevron
        // end felt reliable. Drawing is unchanged — this only grows the region
        // `contentShape` hands to the two gestures below.
        .padding(Self.touchInset)
        .contentShape(Rectangle())
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            onExpand()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            WKInterfaceDevice.current().play(.success)
            onSkip()
        }
    }

    /// Transparent touch margin on every side of the drawn pill. Whoever
    /// positions the pill must compensate for it — see `WorkoutRestTimerOverlay`.
    static let touchInset: CGFloat = 8

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
