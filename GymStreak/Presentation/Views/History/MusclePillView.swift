//
//  MusclePillView.swift
//  GymStreak
//

import SwiftUI

/// Pill-shaped button in the Fortschritt tab's horizontal muscle-group filter.
/// Shows a group name, exercise count, and the average trend % for exercises in that group.
struct MusclePillView: View {
    let title: String
    let subtitle: String
    let trend: Double?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .kerning(-0.2)
                    .foregroundStyle(foregroundColor)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(subtitleColor)
                    if let trend {
                        Text(trendLabel(trend))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(trendColor(for: trend))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 92, alignment: .leading)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        isActive ? DesignSystem.Colors.textOnTint : Color.white
    }
    private var subtitleColor: Color {
        isActive ? DesignSystem.Colors.textOnTint.opacity(0.75) : Color.white.opacity(0.55)
    }
    private var backgroundColor: Color {
        isActive ? DesignSystem.Colors.tint : Color.white.opacity(0.05)
    }

    private func trendLabel(_ value: Double) -> String {
        let arrow = value >= 0 ? "↗" : "↘"
        return "\(arrow) \(Int(abs(value.rounded())))%"
    }

    private func trendColor(for value: Double) -> Color {
        if isActive { return DesignSystem.Colors.textOnTint }
        return value >= 0 ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42)
    }
}
