//
//  FortschrittExerciseRowView.swift
//  GymStreak
//

import SwiftUI

/// A single exercise row in the Fortschritt tab: muscle-group badge + name + count + sparkline + trend %.
struct FortschrittExerciseRowView: View {
    let model: FortschrittExerciseModel

    var body: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("progress.workout_count".localized(model.workoutCount))
                    if model.lastPerformed != nil {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 2, height: 2)
                        Text(relativeDate(model.lastPerformed ?? Date()))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                MiniSparkline(
                    data: model.sparkline,
                    color: trendColor
                )
                if let trend = model.trendPct {
                    Text(trendLabel(trend))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trendColor)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var badge: some View {
        Text(String(model.primaryMuscleGroup.prefix(2)).uppercased())
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .kerning(-0.3)
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .frame(width: 42, height: 42)
            .background(DesignSystem.Colors.tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var trendColor: Color {
        guard let trend = model.trendPct else { return DesignSystem.Colors.tint }
        return trend >= 0 ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42)
    }

    private func trendLabel(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))%"
    }

    // Hoisted out of `body`: this was allocated once per row, per render
    // (docs/history-performance.md §2.7). `@MainActor` because RelativeDateTimeFormatter carries no
    // documented thread-safety guarantee, so sharing one instance is only sound while every access
    // is from a view body on the main thread.
    @MainActor
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
