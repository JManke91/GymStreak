//
//  TrainingsTabView.swift
//  GymStreak
//

import SwiftUI

/// The Trainings sub-tab: WeekHero + List/Calendar toggle + month-grouped workout list or calendar view.
struct TrainingsTabView: View {
    let sessions: [WorkoutSession]
    let prExerciseCountBySession: [UUID: Int]
    let onDeleteRequested: (WorkoutSession) -> Void

    enum DisplayMode: String, CaseIterable {
        case list, calendar
    }

    @State private var mode: DisplayMode = .list

    var body: some View {
        VStack(spacing: 14) {
            WeekHeroView(
                weekStats: HistoryStatsService.weekStats(
                    sessions: sessions,
                    prExerciseCountBySession: prExerciseCountBySession
                ),
                weekDays: HistoryStatsService.weekDayStatuses(sessions: sessions)
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
