//
//  AISparkleView.swift
//  GymStreak
//
//  4-point bespoke sparkle icon — the primary AI Coach identity mark.
//  Drawn with SwiftUI Canvas/Path; does NOT use SF Symbols.
//

import SwiftUI

/// Bespoke 4-point sparkle that serves as the AI Coach identity mark.
///
/// Scales from 12 pt (inline) to 88 pt (hero). Matches the SVG geometry in the
/// design reference exactly: one large 4-point star centred at (12,12) in a
/// 24×24 viewBox plus two smaller accent stars at top-right and bottom-left.
struct AISparkleView: View {

    // MARK: - Props

    var size: CGFloat = 16
    var color: Color = AICoachTheme.accent
    /// Adds a soft radial-blur halo behind the sparkle.
    var glow: Bool = false
    /// Applies the aiPulse animation (scale 0.92→1.08, opacity 0.45→1.0) on a 1.4s loop.
    var pulse: Bool = false

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation state

    /// Drives the scale/opacity oscillation when pulsing.
    @State private var pulsing = false

    // MARK: - Body

    var body: some View {
        ZStack {
            if glow {
                // Radial blur halo
                RadialGradient(
                    gradient: Gradient(colors: [color.opacity(0.4), Color.clear]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.8
                )
                .blur(radius: 4)
                .frame(width: size * 1.5, height: size * 1.5)
            }

            Canvas { ctx, canvasSize in
                let s = canvasSize.width
                // Scale factor: design SVG is 24×24
                let scale = s / 24.0

                // --- Large 4-point star ---
                // Path: M12 2 L13.6 9.2 L21 11 L13.6 12.8 L12 20 L10.4 12.8 L3 11 L10.4 9.2 Z
                var star = Path()
                star.move(to:    CGPoint(x: 12 * scale, y:  2 * scale))
                star.addLine(to: CGPoint(x: 13.6 * scale, y:  9.2 * scale))
                star.addLine(to: CGPoint(x: 21 * scale, y: 11 * scale))
                star.addLine(to: CGPoint(x: 13.6 * scale, y: 12.8 * scale))
                star.addLine(to: CGPoint(x: 12 * scale, y: 20 * scale))
                star.addLine(to: CGPoint(x: 10.4 * scale, y: 12.8 * scale))
                star.addLine(to: CGPoint(x:  3 * scale, y: 11 * scale))
                star.addLine(to: CGPoint(x: 10.4 * scale, y:  9.2 * scale))
                star.closeSubpath()
                ctx.fill(star, with: .color(color))

                // --- Top-right small star (opacity 0.85) ---
                // M19 4 L19.5 6 L21.5 6.5 L19.5 7 L19 9 L18.5 7 L16.5 6.5 L18.5 6 Z
                var starSm1 = Path()
                starSm1.move(to:    CGPoint(x: 19   * scale, y: 4   * scale))
                starSm1.addLine(to: CGPoint(x: 19.5 * scale, y: 6   * scale))
                starSm1.addLine(to: CGPoint(x: 21.5 * scale, y: 6.5 * scale))
                starSm1.addLine(to: CGPoint(x: 19.5 * scale, y: 7   * scale))
                starSm1.addLine(to: CGPoint(x: 19   * scale, y: 9   * scale))
                starSm1.addLine(to: CGPoint(x: 18.5 * scale, y: 7   * scale))
                starSm1.addLine(to: CGPoint(x: 16.5 * scale, y: 6.5 * scale))
                starSm1.addLine(to: CGPoint(x: 18.5 * scale, y: 6   * scale))
                starSm1.closeSubpath()
                ctx.fill(starSm1, with: .color(color.opacity(0.85)))

                // --- Bottom-left small star (opacity 0.70) ---
                // M5 16 L5.4 17.4 L6.8 17.8 L5.4 18.2 L5 19.6 L4.6 18.2 L3.2 17.8 L4.6 17.4 Z
                var starSm2 = Path()
                starSm2.move(to:    CGPoint(x: 5   * scale, y: 16   * scale))
                starSm2.addLine(to: CGPoint(x: 5.4 * scale, y: 17.4 * scale))
                starSm2.addLine(to: CGPoint(x: 6.8 * scale, y: 17.8 * scale))
                starSm2.addLine(to: CGPoint(x: 5.4 * scale, y: 18.2 * scale))
                starSm2.addLine(to: CGPoint(x: 5   * scale, y: 19.6 * scale))
                starSm2.addLine(to: CGPoint(x: 4.6 * scale, y: 18.2 * scale))
                starSm2.addLine(to: CGPoint(x: 3.2 * scale, y: 17.8 * scale))
                starSm2.addLine(to: CGPoint(x: 4.6 * scale, y: 17.4 * scale))
                starSm2.closeSubpath()
                ctx.fill(starSm2, with: .color(color.opacity(0.70)))
            }
            .frame(width: size, height: size)
        }
        // Pulse: scale 0.92→1.08, opacity 0.45→1.0 on a 1.4s easeInOut loop
        .scaleEffect(pulse && pulsing && !reduceMotion ? 1.08 : 1.0)
        .opacity(pulse && pulsing && !reduceMotion ? 1.0 : (pulse && !reduceMotion ? 0.45 : 1.0))
        .onAppear {
            guard pulse, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .onChange(of: pulse) { _, newValue in
            if newValue, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                pulsing = false
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                pulsing = false
            } else if pulse {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Sizes") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        HStack(spacing: 20) {
            AISparkleView(size: 12)
            AISparkleView(size: 16)
            AISparkleView(size: 24)
            AISparkleView(size: 48, glow: true)
            AISparkleView(size: 88, glow: true)
        }
        .padding()
    }
}

#Preview("Pulse + Glow") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        HStack(spacing: 32) {
            AISparkleView(size: 32, pulse: true)
            AISparkleView(size: 32, glow: true, pulse: true)
            AISparkleView(size: 32, color: AICoachTheme.warningAccent, glow: true)
        }
        .padding()
    }
}
