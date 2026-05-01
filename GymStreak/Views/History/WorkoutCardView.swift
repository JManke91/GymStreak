//
//  WorkoutCardView.swift
//  GymStreak
//

import SwiftUI

/// A single workout row in the Trainings list (and in the calendar selected-day detail).
/// Layout: date block | type + stats | intensity ring.
struct WorkoutCardView: View {
    let workout: WorkoutSession
    let isPR: Bool
    let prLifts: Int

    private var workoutType: WorkoutType {
        WorkoutType.classify(routineName: workout.routineName)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            dateBlock
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                metricsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IntensityRing(value: workout.completionPercentage)
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Date block

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(dowText)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.45))
            Text("\(day)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(monthText.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(width: 50)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Title + PR badge

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(workout.routineName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            WorkoutTypeChip(type: workoutType, size: .small)
            if isPR {
                prBadge
            }
        }
    }

    private var prBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9, weight: .bold))
            Text("history.pr.count".localized(prLifts))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(red: 1, green: 0.8, blue: 0).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Metrics row

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricLabel(icon: "clock", text: "\(durationMinutes)m")
            metricLabel(icon: "dumbbell", text: "history.card.sets".localized(workout.completedSetsCount))
            metricLabel(icon: "bolt", text: formatVolume(workout.totalVolume))
        }
        .foregroundStyle(Color.white.opacity(0.6))
        .font(.system(size: 12))
    }

    private func metricLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .monospacedDigit()
        }
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        } else {
            return "\(Int(kg))kg"
        }
    }

    // MARK: - Date formatting

    private var dowText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt.string(from: workout.startTime).uppercased()
    }

    private var day: Int {
        Calendar.current.component(.day, from: workout.startTime)
    }

    private var monthText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMM")
        return fmt.string(from: workout.startTime)
    }

    private var durationMinutes: Int {
        max(0, Int(workout.duration / 60))
    }
}
