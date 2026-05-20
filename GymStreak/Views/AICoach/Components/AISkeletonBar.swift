//
//  AISkeletonBar.swift
//  GymStreak
//
//  Horizontal shimmer bar used in the "generating" skeleton state.
//  Gradient travels left-to-right using a phase-animated linear gradient.
//

import SwiftUI

/// A shimmering horizontal bar that signals AI content is being generated.
///
/// Uses a moving `[white04, accent10, white04]` gradient matching the CSS
/// `skeletonShimmer` animation in the design spec. When `accessibilityReduceMotion`
/// is active it renders as a static muted bar instead.
struct AISkeletonBar: View {

    // MARK: - Props

    var width: CGFloat? = nil  // nil = .infinity
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 4

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var phase: CGFloat = 0

    // MARK: - Body

    var body: some View {
        Group {
            if reduceMotion {
                staticBar
            } else {
                animatedBar
            }
        }
        .frame(maxWidth: width ?? .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear(perform: startAnimation)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var staticBar: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
    }

    @ViewBuilder
    private var animatedBar: some View {
        // Phase drives the shimmer; we shift stop locations by `phase`
        // so the highlight sweeps from left to right repeatedly.
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.04),              location: clamp(0.0 + phase)),
                .init(color: AICoachTheme.accent.opacity(0.10),      location: clamp(0.5 + phase)),
                .init(color: Color.white.opacity(0.04),              location: clamp(1.0 + phase)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat) -> CGFloat {
        // Keep locations in [0,1] for LinearGradient — the wrap-around effect
        // creates the illusion of a continuous sweep without needing a tiling gradient.
        (value.truncatingRemainder(dividingBy: 1.0) + 1.0).truncatingRemainder(dividingBy: 1.0)
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        // Animate phase from 0→1 on a 1.8s linear loop
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            phase = 1.0
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 12) {
            AISkeletonBar()
            AISkeletonBar(width: 200, height: 10)
            AISkeletonBar(width: 140, height: 8, cornerRadius: 3)
        }
        .padding()
    }
}

#Preview("Reduce Motion") {
    // Use a helper that forces reduce-motion via a custom environment override wrapper
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 12) {
            // Static bars — reduce motion is simulated by passing the env flag via a wrapper
            AISkeletonBar()
            AISkeletonBar(width: 180)
        }
        .padding()
    }
    // Note: \.accessibilityReduceMotion is read-only on iOS 26; test via Simulator Accessibility settings.
}
