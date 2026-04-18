//
//  ChartSupportViews.swift
//  GymStreak
//

import SwiftUI

// MARK: - Summary Stats View

struct SummaryStatsView: View {
    @ObservedObject var viewModel: ExerciseProgressViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Personal Record
            StatCard(
                title: "chart.personal_record".localized,
                value: viewModel.personalRecordString ?? "-",
                icon: "trophy.fill",
                iconColor: .yellow
            )

            // Trend
            StatCard(
                title: "chart.trend".localized,
                value: viewModel.trendPercentageString ?? "-",
                icon: viewModel.trendIsPositive ? "arrow.up.right" : "arrow.down.right",
                iconColor: viewModel.trendIsPositive ? DesignSystem.Colors.success : DesignSystem.Colors.warning
            )

            // Sessions
            StatCard(
                title: "chart.sessions".localized,
                value: viewModel.sessionCountString ?? "-",
                icon: "figure.strengthtraining.traditional",
                iconColor: DesignSystem.Colors.tint
            )
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)

            Text(value)
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty Chart View

struct EmptyChartView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: 4) {
                Text("chart.empty.title".localized)
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("chart.empty.message".localized)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
