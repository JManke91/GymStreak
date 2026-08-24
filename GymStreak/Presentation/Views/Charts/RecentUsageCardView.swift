//
//  RecentUsageCardView.swift
//  GymStreak
//
//  Extracted from ExerciseProgressChartView (2026-08-23) when the "Letzte Sätze"
//  list became one card per usage: the card is self-contained and the chart view
//  was already far past this project's file-size convention.
//

import SwiftUI

/// One card of the "recent sets" list: the sets of **one usage** within one workout.
///
/// A workout that trained the exercise twice renders two of these, one per usage, so
/// the card names the usage it belongs to — otherwise two cards sharing a date read as
/// a contradiction rather than as two different pieces of work.
struct RecentUsageCardView: View {
    let entry: ExerciseRecentUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            setsRow
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                dateBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text("history.card.sets".localized(entry.sets.count))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    if let best = entry.bestSet {
                        Text(
                            String(
                                format: "history.exercise.best_set".localized,
                                String(format: "%gkg × %d", best.weight, best.reps)
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(relativeDate)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
                usageBadge
            }
        }
    }

    /// Which usage these sets came from — the slot's rep-range goal and the routine it
    /// was performed in. History with no slot at all says so explicitly rather than
    /// borrowing another usage's label.
    private var usageBadge: some View {
        Text(usageLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }

    /// The shared label — the same string the usage picker names this slot with. Two
    /// names for one usage would make the picker unusable, so there is one implementation
    /// (`ExerciseUsage.displayLabel`) rather than a copy per surface.
    private var usageLabel: String { entry.usage.displayLabel }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text("\(dayNumber)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(monthLabel.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(width: 38, height: 38)
        .background(DesignSystem.Colors.tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // Hoisted out of `body`'s read path: both used to be allocated per row per render.
    // `Locale.current` is the default for both, so it does not need setting.
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var dayNumber: Int { Calendar.current.component(.day, from: entry.date) }

    private var monthLabel: String {
        Self.monthFormatter.string(from: entry.date)
    }

    private var relativeDate: String {
        Self.relativeFormatter.localizedString(for: entry.date, relativeTo: Date())
    }

    private var setsRow: some View {
        HStack(spacing: 6) {
            ForEach(entry.sets) { set in
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: "%g", set.weight))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        Text("kg")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Text("\(set.reps) \("history.detail.reps".localized)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
