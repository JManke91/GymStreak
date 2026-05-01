//
//  HistoryCalendarView.swift
//  GymStreak
//

import SwiftUI

/// iOS-style month calendar showing completed workouts as colored dots per workout type.
/// Tap a day to reveal its workout card below the grid.
struct HistoryCalendarView: View {
    let sessions: [WorkoutSession]
    let prExerciseCountBySession: [UUID: Int]

    @State private var viewMonth: Date = HistoryCalendarView.initialMonth()
    @State private var selectedDate: Date?

    private static func initialMonth() -> Date {
        let cal = HistoryStatsService.isoGermanCalendar()
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    private var calendar: Calendar { HistoryStatsService.isoGermanCalendar() }

    private var sessionsByDay: [Date: WorkoutSession] {
        var map: [Date: WorkoutSession] = [:]
        for session in sessions where session.endTime != nil {
            let day = calendar.startOfDay(for: session.startTime)
            // If two finished workouts on the same day, prefer the most recent.
            if let existing = map[day] {
                if session.startTime > existing.startTime {
                    map[day] = session
                }
            } else {
                map[day] = session
            }
        }
        return map
    }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            grid
            legend
            selectedDaySection
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        let year = calendar.component(.year, from: viewMonth)
        let month = calendar.component(.month, from: viewMonth)
        let stats = HistoryStatsService.monthStats(sessions: sessions, year: year, month: month)

        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthStatsLabel(stats: stats).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(monthLabel())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .kerning(-0.5)
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            Spacer()
            HStack(spacing: 6) {
                iconButton(systemName: "chevron.left") { changeMonth(-1) }
                iconButton(systemName: "chevron.right") { changeMonth(1) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: viewMonth) {
            viewMonth = next
        }
    }

    private func monthLabel() -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return fmt.string(from: viewMonth)
    }

    private func monthStatsLabel(stats: (sessions: Int, volume: Double)) -> String {
        let volumeTxt: String
        if stats.volume >= 1000 {
            volumeTxt = String(format: "%.1ft", stats.volume / 1000)
        } else {
            volumeTxt = "\(Int(stats.volume))kg"
        }
        return String(format: "history.calendar.month_stats".localized, stats.sessions, volumeTxt)
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { idx in
                Text(weekdaySymbol(for: idx))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(idx >= 5 ? Color.white.opacity(0.35) : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func weekdaySymbol(for mondayIndex: Int) -> String {
        // mondayIndex: 0=Monday ... 6=Sunday (German locale)
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale.current
        let symbols = fmt.veryShortStandaloneWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
        // veryShortStandaloneWeekdaySymbols[0] = Sunday in Gregorian; transform to Monday-first.
        let gregorianIndex = (mondayIndex + 1) % 7
        return String(symbols[gregorianIndex].prefix(1)).uppercased()
    }

    // MARK: - Grid

    private var grid: some View {
        let cells = buildCells()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(cells) { cell in
                dayCell(cell)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private struct DayCell: Identifiable {
        let id = UUID()
        let date: Date
        let day: Int
        let isOutside: Bool
        let isToday: Bool
        let session: WorkoutSession?
    }

    private func buildCells() -> [DayCell] {
        let firstOfMonth = viewMonth
        let lastOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstOfMonth) ?? firstOfMonth

        var cells: [DayCell] = []
        let firstWeekday = ((calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday) + 7) % 7
        let today = calendar.startOfDay(for: Date())
        let map = sessionsByDay

        // Preceding month tail
        if firstWeekday > 0 {
            let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) ?? firstOfMonth
            let prevMonthDayCount = calendar.range(of: .day, in: .month, for: prevMonthStart)?.count ?? 30
            for offset in stride(from: firstWeekday - 1, through: 0, by: -1) {
                let day = prevMonthDayCount - offset
                var comps = calendar.dateComponents([.year, .month], from: prevMonthStart)
                comps.day = day
                let date = calendar.date(from: comps) ?? prevMonthStart
                cells.append(DayCell(date: date, day: day, isOutside: true, isToday: false, session: nil))
            }
        }

        // Current month days
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        for d in 1...daysInMonth {
            var comps = calendar.dateComponents([.year, .month], from: firstOfMonth)
            comps.day = d
            let date = calendar.date(from: comps) ?? firstOfMonth
            let startOfDay = calendar.startOfDay(for: date)
            let isToday = startOfDay == today
            cells.append(DayCell(date: startOfDay, day: d, isOutside: false, isToday: isToday, session: map[startOfDay]))
        }

        // Trailing next-month days to complete the last row
        while cells.count % 7 != 0 {
            guard let last = cells.last else { break }
            let next = calendar.date(byAdding: .day, value: 1, to: last.date) ?? last.date
            cells.append(DayCell(date: next, day: calendar.component(.day, from: next), isOutside: true, isToday: false, session: nil))
        }

        // Let lastOfMonth silence "unused" in release builds
        _ = lastOfMonth
        return cells
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCell) -> some View {
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: cell.date) } ?? false
        Button {
            guard !cell.isOutside else { return }
            HapticManager.shared.selection()
            selectedDate = cell.date
        } label: {
            VStack(spacing: 3) {
                Text("\(cell.day)")
                    .font(.system(size: 14, weight: cell.isToday || isSelected ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        cell.isOutside ? Color.white.opacity(0.2)
                        : isSelected ? DesignSystem.Colors.textOnTint
                        : cell.isToday ? DesignSystem.Colors.tint
                        : Color.white
                    )
                dot(for: cell, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.tint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        cell.isToday && !isSelected ? DesignSystem.Colors.tint : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(cell.isOutside)
    }

    @ViewBuilder
    private func dot(for cell: DayCell, isSelected: Bool) -> some View {
        if let session = cell.session, !cell.isOutside {
            let type = WorkoutType.classify(routineName: session.routineName)
            Circle()
                .fill(isSelected ? DesignSystem.Colors.textOnTint : type.color)
                .frame(width: 5, height: 5)
        } else {
            Color.clear.frame(width: 5, height: 5)
        }
    }

    // MARK: - Legend

    private var legendTypes: [WorkoutType] {
        let year = calendar.component(.year, from: viewMonth)
        let month = calendar.component(.month, from: viewMonth)
        var seen = Set<WorkoutType>()
        var ordered: [WorkoutType] = []
        for session in sessions where session.endTime != nil {
            let comps = calendar.dateComponents([.year, .month], from: session.startTime)
            guard comps.year == year, comps.month == month else { continue }
            let type = WorkoutType.classify(routineName: session.routineName)
            if seen.insert(type).inserted {
                ordered.append(type)
            }
        }
        return ordered
    }

    @ViewBuilder
    private var legend: some View {
        let types = legendTypes
        if !types.isEmpty {
            HStack(spacing: 14) {
                ForEach(types, id: \.self) { type in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(type.color)
                            .frame(width: 6, height: 6)
                        Text(type.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Selected day section

    @ViewBuilder
    private var selectedDaySection: some View {
        if let date = selectedDate {
            let session = sessionsByDay[calendar.startOfDay(for: date)]
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedDateLabel(date))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .kerning(-0.3)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                if let session {
                    NavigationLink(value: session.id) {
                        WorkoutCardView(
                            workout: session,
                            isPR: (prExerciseCountBySession[session.id] ?? 0) > 0,
                            prLifts: prExerciseCountBySession[session.id] ?? 0
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 3) {
                        Text("history.calendar.no_workout".localized)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("history.calendar.no_workout.detail".localized)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(0.08),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    )
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private func selectedDateLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("EEE d. MMM")
        return fmt.string(from: date)
    }
}
