//
//  TrainingsTabView.swift
//  GymStreak
//

import SwiftUI

/// The Trainings sub-tab: WeekHero + List/Calendar toggle + month-grouped workout list or calendar view.
struct TrainingsTabView: View {
    let sessions: [WorkoutSession]
    let routines: [Routine]
    let prExerciseCountBySession: [UUID: Int]
    let onDeleteRequested: (WorkoutSession) -> Void

    /// Dynamic weekly plan derived from the user's scheduled routines.
    private var plannedWeek: WorkoutPlanningService.PlannedWeek {
        WorkoutPlanningService.plannedWeek(routines: routines, completedSessions: sessions)
    }

    enum DisplayMode: String, CaseIterable {
        case list, calendar
    }

    @State private var mode: DisplayMode = .list

    // MARK: - AI Coach entry card state

    private let coordinator = ProactivePromptCoordinator.shared
    private let preferences = AICoachPreferences.shared
    private let availability = AICoachAvailability.shared

    /// Whether conditions are met to show any AI Coach card.
    private var shouldShowCoachCards: Bool {
        availability.isAvailable
            && preferences.isPeriodRecapEffectivelyEnabled
            && sessions.count >= 3
    }

    /// Default range: lastMonth if we're early in the month (day <= 5), else thisMonth.
    private var defaultEntryRange: PeriodRange {
        Calendar.current.component(.day, from: Date()) <= 5 ? .lastMonth : .thisMonth
    }

    /// Lightweight last-month stats for the entry card subline.
    private var lastMonthStats: (count: Int, volumeTons: Double, prs: Int) {
        let calendar = Calendar.current
        let now = Date()
        guard let prevDate = calendar.date(byAdding: .month, value: -1, to: now),
              let interval = calendar.dateInterval(of: .month, for: prevDate) else {
            return (0, 0, 0)
        }
        let prev = sessions.filter {
            $0.endTime != nil && $0.startTime >= interval.start && $0.startTime < interval.end
        }
        let vol = prev.reduce(0.0) { $0 + $1.totalVolume } / 1000.0
        let prs = prev.reduce(0) { $0 + (prExerciseCountBySession[$1.id] ?? 0) }
        return (prev.count, vol, prs)
    }

    /// Label for the last completed month.
    private var lastMonthLabel: String {
        let calendar = Calendar.current
        let now = Date()
        guard let prevDate = calendar.date(byAdding: .month, value: -1, to: now),
              let interval = calendar.dateInterval(of: .month, for: prevDate) else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return fmt.string(from: interval.start)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Proactive monthly prompt (above everything else)
            if coordinator.shouldShow {
                ProactivePeriodPromptCard(
                    monthLabel: coordinator.monthLabel,
                    sessionCount: coordinator.sessionCount,
                    totalVolumeTons: coordinator.totalVolumeTons,
                    newPRCount: coordinator.newPRCount,
                    destination: PeriodRecapDestination(range: .lastMonth),
                    onDismiss: { coordinator.dismiss() }
                )
                .padding(.horizontal, 16)
            }

            // Coach entry card
            if shouldShowCoachCards && !coordinator.shouldShow {
                let stats = lastMonthStats
                CoachEntryCard(
                    periodLabel: lastMonthLabel,
                    sessionCount: stats.count,
                    totalVolumeTons: stats.volumeTons,
                    newPRCount: stats.prs,
                    destination: PeriodRecapDestination(range: defaultEntryRange)
                )
                .padding(.horizontal, 16)
            }

            WeekHeroView(
                weekStats: HistoryStatsService.weekStats(
                    sessions: sessions,
                    prExerciseCountBySession: prExerciseCountBySession,
                    goal: plannedWeek.goal
                ),
                weekDays: HistoryStatsService.weekDayStatuses(
                    sessions: sessions,
                    plannedDates: plannedWeek.plannedDates
                )
            )
            .padding(.horizontal, 16)

            filterBar

            if mode == .calendar {
                HistoryCalendarView(
                    sessions: sessions,
                    prExerciseCountBySession: prExerciseCountBySession
                )
            } else {
                listContent
            }
        }
        .onAppear {
            coordinator.evaluate(sessions: sessions, prCountBySession: prExerciseCountBySession)
        }
        .onChange(of: sessions.count) {
            coordinator.evaluate(sessions: sessions, prCountBySession: prExerciseCountBySession)
        }
    }

    // MARK: - Filter / view-mode bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("history.all_trainings".localized)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            segmentedToggle
        }
        .padding(.horizontal, 16)
    }

    private var segmentedToggle: some View {
        HStack(spacing: 0) {
            toggleButton(for: .list, systemName: "list.bullet")
            toggleButton(for: .calendar, systemName: "calendar")
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggleButton(for target: DisplayMode, systemName: String) -> some View {
        Button {
            if mode != target {
                HapticManager.shared.selection()
                mode = target
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(mode == target ? Color.white : Color.white.opacity(0.5))
                .frame(width: 32, height: 26)
                .background(mode == target ? Color.white.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        if sessions.isEmpty {
            ContentUnavailableView {
                Label("history.empty.title".localized, systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("history.empty.description".localized)
            }
            .padding(.top, 40)
        } else {
            let groups = HistoryStatsService.groupByMonth(sessions: sessions)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 {
                        monthDivider(for: group)
                    }
                    workoutList(for: group)
                }
            }
        }
    }

    private func monthDivider(for group: HistoryStatsService.MonthSectionInfo) -> some View {
        HStack {
            Text(group.label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .foregroundStyle(Color.white)
            Spacer()
            Text(monthSummary(for: group))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func monthSummary(for group: HistoryStatsService.MonthSectionInfo) -> String {
        let volumeTxt: String
        if group.totalVolume >= 1000 {
            volumeTxt = String(format: "%.0ft", group.totalVolume / 1000)
        } else {
            volumeTxt = "\(Int(group.totalVolume))kg"
        }
        return String(format: "history.month.summary".localized, group.sessions.count, volumeTxt)
    }

    private func workoutList(for group: HistoryStatsService.MonthSectionInfo) -> some View {
        VStack(spacing: 8) {
            ForEach(group.sessions) { session in
                NavigationLink(value: session.id) {
                    WorkoutCardView(
                        workout: session,
                        isPR: (prExerciseCountBySession[session.id] ?? 0) > 0,
                        prLifts: prExerciseCountBySession[session.id] ?? 0
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
                .contextMenu {
                    Button(role: .destructive) {
                        onDeleteRequested(session)
                    } label: {
                        Label("action.delete".localized, systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
