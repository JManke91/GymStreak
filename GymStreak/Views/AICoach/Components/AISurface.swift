//
//  AISurface.swift
//  GymStreak
//
//  Card chrome that wraps any AI-generated content.
//  Visual spec: gradient border (1.5 pt), accent-washed inner surface,
//  top-right radial glow, sparkle + label header, optional streaming indicator,
//  optional regenerate button, optional privacy footer.
//

import SwiftUI

/// Chrome wrapper for all AI Coach generated content.
///
/// Renders a 1.5-pt gradient border, an accent-tinted inner background,
/// a top-right radial glow, a sparkle + "COACH" header row, and an optional
/// on-device privacy footer. When `isStreaming` is `true` the border shimmers
/// and the sparkle pulses.
struct AISurface<Content: View>: View {

    // MARK: - Props

    var isStreaming: Bool = false
    var showFooter: Bool = true
    var headerLabel: String = "COACH"
    /// Tighter vertical padding for compact contexts.
    var compact: Bool = false
    var onRegenerate: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Animation state

    /// Drives the continuous 2.4s shimmer on the border gradient.
    @State private var shimmerPhase: CGFloat = 0

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(headerPadding)
            contentBody
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, compact ? 14 : 16)
            if showFooter {
                footerRow
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, compact ? 14 : 16)
            }
        }
        .background(alignment: .topTrailing) {
            // Top-right radial glow
            RadialGradient(
                gradient: Gradient(colors: [
                    AICoachTheme.accent.opacity(0.13),
                    Color.clear,
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 70
            )
            .frame(width: 140, height: 140)
            .offset(x: 40, y: -40)
            .allowsHitTesting(false)
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: AICoachTheme.surfaceCorner, style: .continuous)
                    .fill(borderGradient)
                RoundedRectangle(cornerRadius: AICoachTheme.innerCorner, style: .continuous)
                    .fill(innerGradient)
                    .padding(AICoachTheme.borderWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AICoachTheme.surfaceCorner, style: .continuous))
        .onAppear(perform: startShimmer)
        .onChange(of: isStreaming) { _, streaming in
            if streaming { startShimmer() }
        }
    }

    // MARK: - Border

    private var borderGradient: LinearGradient {
        if isStreaming && !reduceMotion {
            // Animated shimmer gradient: shifts horizontally
            return LinearGradient(
                stops: [
                    .init(color: AICoachTheme.accent.opacity(0.4), location: 0 + shimmerPhase),
                    .init(color: AICoachTheme.accent.opacity(0.10), location: 0.25 + shimmerPhase),
                    .init(color: AICoachTheme.accent.opacity(0.4), location: 0.5 + shimmerPhase),
                    .init(color: AICoachTheme.accent.opacity(0.10), location: 0.75 + shimmerPhase),
                    .init(color: AICoachTheme.accent.opacity(0.4), location: 1.0 + shimmerPhase),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            // Static accent gradient at 140° equivalent
            return LinearGradient(
                stops: [
                    .init(color: AICoachTheme.accent.opacity(0.33), location: 0.00),
                    .init(color: AICoachTheme.accent.opacity(0.063), location: 0.38),
                    .init(color: Color.white.opacity(0.04), location: 0.70),
                    .init(color: AICoachTheme.accent.opacity(0.19), location: 1.00),
                ],
                startPoint: UnitPoint(x: 0.1, y: 0.0),
                endPoint: UnitPoint(x: 0.9, y: 1.0)
            )
        }
    }

    private var innerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AICoachTheme.accent.opacity(0.06), location: 0.00),
                .init(color: AICoachTheme.accent.opacity(0.02), location: 0.30),
                .init(color: Color.white.opacity(0.02),         location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 8) {
            AISparkleView(size: 15, color: AICoachTheme.accent, pulse: isStreaming)

            Text(headerLabel)
                .font(AICoachTheme.mono(size: 10))
                .foregroundStyle(AICoachTheme.accent)
                .kerning(1.6) // ~0.16em at 10 pt
                .textCase(.uppercase)

            if isStreaming {
                streamingIndicator
            }

            Spacer(minLength: 0)

            if let regenerate = onRegenerate, !isStreaming {
                Button(action: regenerate) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ai_coach.regenerate_button".localized)
            }
        }
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            // Small pulsing dot
            PulsingDot(color: AICoachTheme.accent, reduceMotion: reduceMotion)

            Text("ai_coach.streaming_label".localized)
                .font(AICoachTheme.mono(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.45))
                .kerning(0.4)
        }
        .padding(.leading, 4)
    }

    // MARK: - Content body

    @ViewBuilder
    private var contentBody: some View {
        content()
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.05))
                .padding(.bottom, 10)

            AIPrivacyFooter(tone: .inline)
        }
        .padding(.top, 12)
    }

    // MARK: - Layout helpers

    private var horizontalPadding: CGFloat { compact ? 16 : 18 }

    private var headerPadding: EdgeInsets {
        EdgeInsets(
            top: compact ? 14 : 16,
            leading: horizontalPadding,
            bottom: 10,
            trailing: horizontalPadding
        )
    }

    // MARK: - Shimmer animation

    private func startShimmer() {
        guard isStreaming, !reduceMotion else { return }
        shimmerPhase = 0
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.0
        }
    }
}

// MARK: - Pulsing dot sub-view

private struct PulsingDot: View {
    let color: Color
    let reduceMotion: Bool

    @State private var opacity: Double = 0.45

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
            .opacity(opacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}

// MARK: - Previews

#Preview("Static") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        AISurface(showFooter: true) {
            Text("Solider Push-Tag — Volumen leicht unter Schnitt der letzten vier Wochen, dafür neue Bestleistung bei Bench Press.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineSpacing(4)
        }
        .padding()
    }
}

#Preview("Streaming") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        AISurface(isStreaming: true, showFooter: false, compact: true) {
            Text("Solider Push-Tag — Volumen leicht unter Schnitt der letzten vier Wochen.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineSpacing(4)
        }
        .padding()
    }
}

#Preview("With Regenerate") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        AISurface(onRegenerate: { }) {
            Text("Gute Leistung heute. Weiter so!")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .padding()
    }
}
