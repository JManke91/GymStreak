//
//  TrainingsTabView.swift
//  GymStreak
//

import SwiftUI

/// The Trainings sub-tab: WeekHero + List/Calendar toggle + month-grouped workout list or calendar.
///
/// Renders a precomputed `HistorySnapshot` and nothing else. It deliberately holds no
/// `WorkoutSession` and derives no aggregates: every value it shows was computed once in
/// `HistoryViewModel.rebuild`, because doing it here meant five whole-history aggregations on every
/// render and four relationship traversals per visible card (docs/history-performance.md).
struct TrainingsTabView: View {
    let snapshot: HistorySnapshot
    let aiCoachPreferences: AICoachPreferencesProviding
    let aiCoachAvailability: AICoachAvailabilityProviding
    let proactivePromptCoordinator: ProactivePromptCoordinating
    /// False until the first snapshot build finishes. Without it, the first body evaluation — which
    /// necessarily happens before `.task` can run — renders the empty snapshot and briefly tells the
    /// user they have no workouts.
    let hasLoaded: Bool
    let didFailLoading: Bool
    let onRetry: () -> Void
    let onDeleteRequested: (UUID) -> Void
    /// Pushes a workout detail screen from calendar mode. List rows navigate
    /// through native `NavigationLink`s.
    let onSelectWorkout: (UUID) -> Void

    enum DisplayMode: String, CaseIterable {
        case list, calendar
    }

    @State private var mode: DisplayMode = .list

    // MARK: - AI Coach entry card state

    /// Whether conditions are met to show any AI Coach card.
    private var shouldShowCoachCards: Bool {
        aiCoachAvailability.isAvailable
            && aiCoachPreferences.isPeriodRecapEffectivelyEnabled
            && snapshot.sessionCount >= 3
    }

    /// Default range: lastMonth if we're early in the month (day <= 5), else thisMonth.
    private var defaultEntryRange: PeriodRange {
        Calendar.current.component(.day, from: Date()) <= 5 ? .lastMonth : .thisMonth
    }

    var body: some View {
        VStack(spacing: 14) {
            // Proactive monthly prompt (above everything else)
            if proactivePromptCoordinator.shouldShow {
                ProactivePeriodPromptCard(
                    monthLabel: proactivePromptCoordinator.monthLabel,
                    sessionCount: proactivePromptCoordinator.sessionCount,
                    totalVolumeTons: proactivePromptCoordinator.totalVolumeTons,
                    newPRCount: proactivePromptCoordinator.newPRCount,
                    destination: PeriodRecapDestination(range: .lastMonth),
                    onDismiss: { proactivePromptCoordinator.dismiss() }
                )
                .padding(.horizontal, 16)
            }

            // Coach entry card
            if shouldShowCoachCards && !proactivePromptCoordinator.shouldShow {
                CoachEntryCard(
                    periodLabel: snapshot.lastMonth.label,
                    sessionCount: snapshot.lastMonth.count,
                    totalVolumeTons: snapshot.lastMonth.volumeTons,
                    newPRCount: snapshot.lastMonth.prs,
                    destination: PeriodRecapDestination(range: defaultEntryRange)
                )
                .padding(.horizontal, 16)
            }

            WeekHeroView(
                weekStats: snapshot.weekStats,
                weekDays: snapshot.weekDays
            )
            .padding(.horizontal, 16)

            filterBar

            if mode == .calendar {
                HistoryCalendarView(
                    cardsByDay: snapshot.cardsByDay,
                    monthTotals: snapshot.monthTotals,
                    typesByMonth: snapshot.typesByMonth
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
        if !hasLoaded {
            if didFailLoading {
                ContentUnavailableView {
                    Label("history.load_error.title".localized, systemImage: "exclamationmark.triangle")
                } description: {
                    Text("history.load_error.description".localized)
                } actions: {
                    Button("action.try_again".localized, action: onRetry)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 32)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
        } else if snapshot.rows.isEmpty {
            ContentUnavailableView {
                Label("history.empty.title".localized, systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("history.empty.description".localized)
            }
            .padding(.top, 40)
        } else {
            // One flat lazy stack over pre-interleaved rows. Not a lazy stack of month groups each
            // containing a lazy stack of cards: nesting them is an undocumented shape with
            // corroborated reports of scroll stutter and a reproducible hang, and it bought nothing
            // that flattening does not.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.rows) { row in
                    switch row {
                    case .monthHeader(let month):
                        monthDivider(for: month)
                    case .card(let card):
                        cardRow(card)
                    }
                }
            }
        }
    }

    private func monthDivider(for month: MonthSectionModel) -> some View {
        HStack {
            Text(month.label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .foregroundStyle(Color.white)
            Spacer()
            Text(monthSummary(for: month))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
        // 10, not the original 18: the cards now carry their own 8pt bottom padding (the flat stack
        // has no `spacing:`), so 18 here would have grown the gap above a divider to 26pt.
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func monthSummary(for month: MonthSectionModel) -> String {
        let volumeTxt: String
        if month.totalVolume >= 1000 {
            volumeTxt = String(format: "%.0ft", month.totalVolume / 1000)
        } else {
            volumeTxt = "\(Int(month.totalVolume))kg"
        }
        return String(format: "history.month.summary".localized, month.sessionCount, volumeTxt)
    }

    private func cardRow(_ card: WorkoutCardModel) -> some View {
        NavigationLink(value: card.id) {
            WorkoutCardView(card: card)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
        .contextMenu {
            Button(role: .destructive) {
                onDeleteRequested(card.id)
            } label: {
                Label("action.delete".localized, systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("action.delete".localized)) {
            onDeleteRequested(card.id)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
