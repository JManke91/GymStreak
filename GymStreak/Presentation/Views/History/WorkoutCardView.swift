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
    /// Passed in rather than read from the environment: this view is `Equatable`
    /// so SwiftUI can skip unchanged rows, and an `@Environment` property both
    /// breaks the synthesized `==` and would leave it blind to a unit change —
    /// the row would keep its old number under a new unit word.
    let weightUnit: WeightUnit

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HistoryDateBlock(date: card.startTime)
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
            metricLabel(icon: "bolt", text: WeightFormatting.volume(card.totalVolume, in: weightUnit))
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
}
