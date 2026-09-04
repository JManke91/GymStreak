//
//  WorkoutStatGrid.swift
//  GymStreak
//
//  The four-metric summary of a recorded session (Duration / Sets / Volume /
//  Intensity) as it appears under the workout-detail header. Extracted out of
//  `WorkoutDetailView`, where it was a private helper, so the onboarding
//  history slide shows the shipped tiles rather than a redrawn copy.
//

import SwiftUI

/// The four stat tiles in one row. Values are pre-formatted strings — the icon
/// and colour of each metric are fixed, so callers pass only the numbers.
/// Carries no outer margin; the screen supplies it.
struct WorkoutStatGrid: View {
    let durationText: String
    let setsText: String
    let volumeText: String
    let intensityText: String

    var body: some View {
        HStack(spacing: 6) {
            WorkoutStatTile(
                icon: "clock.fill",
                color: Color(red: 90/255, green: 180/255, blue: 255/255),
                value: durationText,
                label: "history.detail.duration".localized
            )
            WorkoutStatTile(
                icon: "dumbbell.fill",
                color: DesignSystem.Colors.tint,
                value: setsText,
                label: "history.detail.sets".localized
            )
            WorkoutStatTile(
                icon: "bolt.fill",
                color: Color(red: 200/255, green: 140/255, blue: 255/255),
                value: volumeText,
                label: "history.detail.volume".localized
            )
            WorkoutStatTile(
                icon: "flame.fill",
                color: Color(red: 255/255, green: 159/255, blue: 90/255),
                value: intensityText,
                label: "history.detail.intensity".localized
            )
        }
    }
}

/// One tile of the grid: tinted icon chip, the value, and an uppercased label.
struct WorkoutStatTile: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .kerning(-0.4)
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    WorkoutStatGrid(
        durationText: "62m",
        setsText: "18",
        volumeText: "7.4t",
        intensityText: "94"
    )
    .padding(.horizontal, 16)
    .background(DesignSystem.Colors.background)
    .preferredColorScheme(.dark)
}
