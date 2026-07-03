//
//  CoachEntryCard.swift
//  GymStreak
//
//  Tappable entry card surfacing the AI Coach period recap from the Trainings tab.
//  Visual: gradient-bordered 22pt rounded rect, sparkle + eyebrow, period label,
//  stat subline, trailing chevron.
//

import SwiftUI

/// Compact entry card shown in `TrainingsTabView` above `WeekHeroView`.
///
/// Provides a quick preview of the most recent completed period and a call-to-action
/// to open the full `PeriodRecapView`. Tap navigates via `NavigationLink(value:)`.
struct CoachEntryCard: View {

    // MARK: - Props

    /// Human-readable period label (e.g. "März 2026").
    let periodLabel: String
    /// Number of sessions in the period.
    let sessionCount: Int
    /// Total lifted volume in metric tons (kg / 1000).
    let totalVolumeTons: Double
    /// Number of new personal records in the period.
    let newPRCount: Int
    /// Navigation destination pushed on tap.
    let destination: PeriodRecapDestination

    // MARK: - Body

    var body: some View {
        NavigationLink(value: destination) {
            cardBody
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
    }

    // MARK: - Card Layout

    private var cardBody: some View {
        contentRow
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(alignment: .topTrailing) {
                topRightGlow
            }
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(borderGradient)
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(innerGradient)
                        .padding(1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var topRightGlow: some View {
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

    private var contentRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Eyebrow
                HStack(spacing: 6) {
                    AISparkleView(size: 12, color: AICoachTheme.accent, glow: false)
                    Text("ai_coach.period_recap.entry_card.eyebrow".localized)
                        .font(AICoachTheme.mono(size: 9))
                        .foregroundStyle(AICoachTheme.accent)
                        .kerning(1.4)
                }

                // Period label
                Text(String(format: "ai_coach.period_recap.entry_card.title".localized, periodLabel))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)

                // Stats subline
                Text(sublineText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    // MARK: - Helpers

    private var sublineText: String {
        let volumeText: String
        if totalVolumeTons >= 1 {
            volumeText = String(format: "%.1ft", totalVolumeTons)
        } else {
            volumeText = String(format: "%.0fkg", totalVolumeTons * 1000)
        }
        return String(format: "ai_coach.period_recap.entry_card.subline".localized, sessionCount, volumeText, newPRCount)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AICoachTheme.accent.opacity(0.33), location: 0.00),
                .init(color: AICoachTheme.accent.opacity(0.06), location: 0.38),
                .init(color: Color.white.opacity(0.04), location: 0.70),
                .init(color: AICoachTheme.accent.opacity(0.19), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.1, y: 0.0),
            endPoint: UnitPoint(x: 0.9, y: 1.0)
        )
    }

    private var innerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AICoachTheme.accent.opacity(0.06), location: 0.00),
                .init(color: AICoachTheme.accent.opacity(0.02), location: 0.30),
                .init(color: Color.white.opacity(0.02), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachEntryCard(
            periodLabel: "März 2026",
            sessionCount: 14,
            totalVolumeTons: 52.4,
            newPRCount: 4,
            destination: PeriodRecapDestination(range: .lastMonth)
        )
        .padding(.horizontal, 16)
    }
}
