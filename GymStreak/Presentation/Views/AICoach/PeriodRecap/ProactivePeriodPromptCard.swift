//
//  ProactivePeriodPromptCard.swift
//  GymStreak
//
//  Full-width gradient-bordered card shown at the top of TrainingsTabView
//  on the first launch of a new month, prompting the user to view their monthly recap.
//

import SwiftUI

/// Proactive monthly recap prompt card rendered above `CoachEntryCard` in `TrainingsTabView`.
///
/// Shown once per month boundary according to `ProactivePromptCoordinator.shouldShow`.
/// Tapping the primary CTA or "Später" both stamp `lastProactivePromptShownForPeriodId`
/// so the card does not reappear in the same month.
struct ProactivePeriodPromptCard: View {

    // MARK: - Props

    /// Human-readable label for the previous completed month (e.g. "April 2026").
    let monthLabel: String
    let sessionCount: Int
    let totalVolumeTons: Double
    let newPRCount: Int
    /// Navigation destination for the primary CTA.
    let destination: PeriodRecapDestination
    /// Called by both the primary CTA and the dismiss button — coordinator stamps the period id.
    let onDismiss: () -> Void

    // MARK: - State

    @State private var navigateTapped: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            bodyText
            statsRow
            actionRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(alignment: .topTrailing) {
            topRightGlow
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(proactiveBorderGradient)
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
                AICoachTheme.accent.opacity(0.15),
                Color.clear,
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 80
        )
        .frame(width: 160, height: 160)
        .offset(x: 40, y: -40)
        .allowsHitTesting(false)
    }

    // MARK: - Sub-views

    private var topRow: some View {
        HStack {
            HStack(spacing: 6) {
                AISparkleView(size: 14, color: AICoachTheme.accent, glow: true, pulse: true)
                Text("ai_coach.period_recap.proactive.eyebrow".localized)
                    .font(AICoachTheme.mono(size: 9))
                    .foregroundStyle(AICoachTheme.accent)
                    .kerning(1.4)
            }

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ai_coach.period_recap.proactive.dismiss_button".localized)
        }
    }

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "ai_coach.period_recap.proactive.title".localized, monthLabel))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text("ai_coach.period_recap.proactive.subtitle".localized)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AICoachTheme.accent)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            statBadge(value: "\(sessionCount)", label: "ai_coach.period_recap.proactive.stat_sessions".localized)
            statDivider
            statBadge(value: volumeString, label: "ai_coach.period_recap.proactive.stat_volume".localized)
            if newPRCount > 0 {
                statDivider
                statBadge(value: "\(newPRCount) PRs", label: "ai_coach.period_recap.proactive.stat_prs".localized)
            }
        }
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 28)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            // Primary CTA — navigate to PeriodRecapView
            NavigationLink(value: destination) {
                Text("ai_coach.period_recap.proactive.cta_primary".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AICoachTheme.accent)
                    )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                HapticManager.shared.light()
                onDismiss()
            })

            // Secondary — dismiss
            Button(action: onDismiss) {
                Text("ai_coach.period_recap.proactive.cta_later".localized)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var volumeString: String {
        if totalVolumeTons >= 1 {
            return String(format: "%.1ft", totalVolumeTons)
        } else {
            return String(format: "%.0fkg", totalVolumeTons * 1000)
        }
    }

    private var proactiveBorderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AICoachTheme.accent.opacity(0.45), location: 0.00),
                .init(color: AICoachTheme.accent.opacity(0.10), location: 0.40),
                .init(color: Color.white.opacity(0.04), location: 0.70),
                .init(color: AICoachTheme.accent.opacity(0.22), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.0, y: 0.0),
            endPoint: UnitPoint(x: 1.0, y: 1.0)
        )
    }

    private var innerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AICoachTheme.accent.opacity(0.08), location: 0.00),
                .init(color: AICoachTheme.accent.opacity(0.03), location: 0.35),
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
        ProactivePeriodPromptCard(
            monthLabel: "April 2026",
            sessionCount: 14,
            totalVolumeTons: 52.4,
            newPRCount: 3,
            destination: PeriodRecapDestination(range: .lastMonth),
            onDismiss: {}
        )
        .padding(.horizontal, 16)
    }
}
