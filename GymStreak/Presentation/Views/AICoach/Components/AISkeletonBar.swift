//
//  AISkeletonBar.swift
//  GymStreak
//
//  Horizontal shimmer bar used in the "generating" skeleton state.
//  A fixed-stop highlight band travels left-to-right via `.offset` — the
//  stop locations themselves never move.
//

import SwiftUI

/// A shimmering horizontal bar that signals AI content is being generated.
///
/// A `white04` base with a fixed `[clear, accent10, clear]` highlight band
/// swept across it, matching the CSS `skeletonShimmer` animation in the design
/// spec. When `accessibilityReduceMotion` is active it renders as a static
/// muted bar instead.
struct AISkeletonBar: View {

    // MARK: - Props

    var width: CGFloat? = nil  // nil = .infinity
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 4

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    private static let baseColor = Color.white.opacity(0.04)
    private static let highlightColor = AICoachTheme.accent.opacity(0.10)

    /// Fixed, monotonically ascending stops — never mutated.
    ///
    /// `Gradient.Stop.location` must be ordered and `LinearGradient` has no
    /// wrap-around mode, so the sweep is produced by translating this whole
    /// layer with `.offset` (a documented `Animatable` geometry effect) rather
    /// than by shifting the locations, which warned at runtime and made the
    /// highlight jump instead of travel.
    private static let highlightStops: [Gradient.Stop] = [
        .init(color: .clear, location: 0.0),
        .init(color: highlightColor, location: 0.5),
        .init(color: .clear, location: 1.0),
    ]

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
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var staticBar: some View {
        Rectangle()
            .fill(Self.baseColor)
    }

    @ViewBuilder
    private var animatedBar: some View {
        Rectangle()
            .fill(Self.baseColor)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        stops: Self.highlightStops,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    // Travels exactly one bar width off each edge, so at both
                    // ends of the cycle the band is fully clear of the bar and
                    // the `repeatForever` wrap is invisible.
                    .offset(x: (phase * 2 - 1) * proxy.size.width)
                }
            }
            .onAppear(perform: startAnimation)
            // Lands in its own update, so the offset is genuinely back at
            // -width before the next appearance. The reset inside
            // `startAnimation` is coalesced with the `withAnimation` write and
            // cannot re-arm the loop on its own.
            .onDisappear { phase = 0 }
    }

    // MARK: - Helpers

    private func startAnimation() {
        phase = 0
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

/// A paragraph's worth of `AISkeletonBar` rows — full-width lines with a short last one,
/// so the block reads as prose rather than as a filled rectangle.
///
/// Every coach surface that streams a paragraph draws this same shape while it waits, and
/// each one had hand-rolled it. See docs/ai-coach.md § "Streaming".
struct AISkeletonLines: View {

    let count: Int
    var lastLineWidth: CGFloat = 200
    var lineHeight: CGFloat = 12
    var spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                AISkeletonBar(
                    width: index == count - 1 ? lastLineWidth : nil,
                    height: lineHeight
                )
            }
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
