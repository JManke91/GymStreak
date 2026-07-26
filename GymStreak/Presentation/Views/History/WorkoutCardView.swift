//
//  WorkoutCardView.swift
//  GymStreak
//

import SwiftUI

/// A single workout row in the Trainings list (and in the calendar selected-day detail).
/// Layout: date block | type + stats | intensity ring.
///
/// Takes a `WorkoutCardModel`, never a `WorkoutSession`. It previously read `completionPercentage`,
/// `completedSetsCount` and `totalVolume` off the `@Model` object, which is four full traversals of
/// the `workoutExercises → sets` graph per card — re-paid every time a lazy row was rebuilt. Being
/// `Equatable` over plain values also lets SwiftUI skip unchanged rows outright.
struct WorkoutCardView: View, Equatable {
    let card: WorkoutCardModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            dateBlock
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                metricsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IntensityRing(value: card.completionPercentage)
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
            Text(card.routineName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            WorkoutTypeChip(type: card.type, size: .small)
            if card.isPR {
                prBadge
            }
        }
    }

    private var prBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9, weight: .bold))
            Text("history.pr.count".localized(card.prLifts))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(DesignSystem.Colors.pr)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(DesignSystem.Colors.pr.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Metrics row

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricLabel(icon: "clock", text: "\(card.durationMinutes)m")
            metricLabel(icon: "dumbbell", text: "history.card.sets".localized(card.completedSets))
            metricLabel(icon: "bolt", text: formatVolume(card.totalVolume))
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

    // Hoisted out of `body`: these ran twice per card, per render — the dominant per-card cost
    // in the history list (docs/history-performance.md §2.1). `@MainActor` because a shared mutable
    // formatter is only safe while every access comes from a view body; it also keeps these clean
    // when the app target moves to the Swift 6 language mode.
    @MainActor
    private static let dowFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt
    }()

    @MainActor
    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMM")
        return fmt
    }()

    private var dowText: String {
        Self.dowFormatter.string(from: card.startTime).uppercased()
    }

    private var day: Int {
        Calendar.current.component(.day, from: card.startTime)
    }

    private var monthText: String {
        Self.monthFormatter.string(from: card.startTime)
    }
}
