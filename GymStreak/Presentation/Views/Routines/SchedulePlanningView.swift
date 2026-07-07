//
//  SchedulePlanningView.swift
//  GymStreak
//
//  Presentation pieces for routine planning (see docs/workout-planning.md):
//   - `ScheduleFormatter`     localized summary / next-due labels
//   - `RoutineScheduleCard`   tappable summary row shown in RoutineDetailView
//  The editor itself lives in `SchedulePlanningSheet.swift`.
//

import SwiftUI

// MARK: - Formatting

enum ScheduleFormatter {
    /// Short weekday labels keyed by ISO weekday (1 = Monday … 7 = Sunday).
    static func weekdayShortLabels() -> [(weekday: Int, label: String)] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        // shortWeekdaySymbols is [Sun, Mon, … Sat]; reindex to Monday-first ISO.
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        return (1...7).map { w in (w, symbols[w % 7]) }
    }

    /// Human summary of a schedule, e.g. "Alle 3 Tage" or "Mo · Mi · Fr".
    static func summary(type: RoutineScheduleType, intervalDays: Int, weekdays: Set<Int>) -> String {
        switch type {
        case .everyNDays:
            if intervalDays <= 1 { return "schedule.daily".localized }
            return String(format: "schedule.every_n_days".localized, intervalDays)
        case .weekdays:
            guard !weekdays.isEmpty else { return "schedule.weekdays.none".localized }
            let labels = weekdayShortLabels()
            return weekdays.sorted()
                .compactMap { w in labels.first(where: { $0.weekday == w })?.label }
                .joined(separator: " · ")
        }
    }

    /// Relative label for the next-due date used on cards.
    static func nextDueLabel(for date: Date?) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        if target < today { return "schedule.due.overdue".localized }
        if target == today { return "schedule.due.today".localized }
        if calendar.isDateInTomorrow(target) { return "schedule.due.tomorrow".localized }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEE") // weekday name
        return formatter.string(from: target)
    }
}

// MARK: - Summary card (in RoutineDetailView)

struct RoutineScheduleCard: View {
    let schedule: RoutineSchedule?
    let nextDue: Date?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                icon
                label
                Spacer(minLength: 8)
                trailing
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(14)
            .background(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        schedule == nil
                            ? DesignSystem.Colors.tint.opacity(0.18)
                            : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var icon: some View {
        Image(systemName: schedule == nil ? "calendar.badge.plus" : "calendar")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.tint)
            .frame(width: 38, height: 38)
            .background(DesignSystem.Colors.tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("schedule.card.title".localized.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color.white.opacity(0.45))
            if let schedule {
                Text(ScheduleFormatter.summary(
                    type: schedule.type,
                    intervalDays: schedule.intervalDays,
                    weekdays: schedule.weekdays
                ))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            } else {
                Text("schedule.not_planned".localized)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if schedule != nil, let dueLabel = ScheduleFormatter.nextDueLabel(for: nextDue) {
            Text(dueLabel)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.tint.opacity(0.14))
                .clipShape(Capsule())
        } else if schedule == nil {
            Text("schedule.not_planned.cta".localized)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
    }
}
