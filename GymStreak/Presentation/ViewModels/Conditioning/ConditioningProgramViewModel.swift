//
//  ConditioningProgramViewModel.swift
//  GymStreak
//
//  The 12-week conditioning program: enrollment, pause/restart/leave, and the
//  dashboard (phase, week, weekly targets with progress, today's suggestion).
//  One instance lives in `AppDependencies` so the Conditioning screen and the
//  Routines card show the same state. See docs/fight-conditioning.md.
//

import Foundation
import Observation

/// Everything the program screen renders, computed once per `refresh()`.
struct ConditioningProgramDashboard: Equatable {
    let enrollment: ConditioningProgramEnrollment
    let status: ConditioningProgramStatus
    /// All twelve weeks of the user's own plan — the timeline, and the surface
    /// ticket 08 renders blurred for Phases 2–3.
    let weeks: [ConditioningProgramWeek]
    /// The week in progress; week 1 before the start day; `nil` once completed.
    let currentWeek: ConditioningProgramWeek?
    let progress: [ConditioningTargetProgress]
    /// `nil` unless the program is running (not before the start, not paused, not completed).
    let suggestion: ConditioningTodaySuggestion?
}

/// What the Routines tab shows for the program.
enum ConditioningProgramRoutinesCard: Equatable {
    /// Not enrolled and not dismissed: the invitation.
    case invitation
    case enrolled(ConditioningProgramStatus)
}

@Observable
@MainActor
final class ConditioningProgramViewModel {

    private(set) var dashboard: ConditioningProgramDashboard?

    @ObservationIgnored private let store: any ConditioningProgramStoring
    @ObservationIgnored private let conditioningRecords: any ConditioningRecordRepository
    @ObservationIgnored private let workoutSessions: any WorkoutSessionRepository
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(
        store: any ConditioningProgramStoring,
        conditioningRecords: any ConditioningRecordRepository,
        workoutSessions: any WorkoutSessionRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.conditioningRecords = conditioningRecords
        self.workoutSessions = workoutSessions
        self.calendar = calendar
        self.now = now
    }

    /// Read through the observable store, so a view that reads it re-renders when
    /// another device changes the enrollment — the cue to call `refresh()`.
    var enrollment: ConditioningProgramEnrollment? { store.enrollment }

    var routinesCard: ConditioningProgramRoutinesCard? {
        if let enrollment = store.enrollment {
            return .enrolled(ConditioningProgramSchedule.status(on: today, enrollment: enrollment, calendar: calendar))
        }
        return store.isRoutinesCardDismissed ? nil : .invitation
    }

    private var today: ConditioningProgramDay { ConditioningProgramDay(now(), calendar: calendar) }

    // MARK: - Actions

    func enroll(startDate: Date, experience: ConditioningExperience, sparsHard: Bool) {
        store.enrollment = ConditioningProgramEnrollment(
            startDay: ConditioningProgramDay(startDate, calendar: calendar),
            experience: experience,
            sparsHard: sparsHard
        )
        refresh()
    }

    func pause() {
        guard var enrollment = store.enrollment, !enrollment.isPaused else { return }
        enrollment.pausedSince = today
        store.enrollment = enrollment
        refresh()
    }

    func resume() {
        guard var enrollment = store.enrollment, let pausedSince = enrollment.pausedSince else { return }
        if pausedSince < today {
            enrollment.pauses.append(.init(from: pausedSince, until: today))
        }
        enrollment.pausedSince = nil
        store.enrollment = enrollment
        refresh()
    }

    func leave() {
        store.enrollment = nil
        refresh()
    }

    func dismissRoutinesCard() {
        store.isRoutinesCardDismissed = true
    }

    // MARK: - Dashboard

    /// Bounded: at most two small fetches — conditioning since the week began (or
    /// the last few days, for the 48 h rule) and the strength workouts of today.
    func refresh() {
        guard let enrollment = store.enrollment else {
            dashboard = nil
            return
        }
        let now = now()
        let today = ConditioningProgramDay(now, calendar: calendar)
        let status = ConditioningProgramSchedule.status(on: today, enrollment: enrollment, calendar: calendar)
        let weeks = ConditioningProgramContent.weeks(experience: enrollment.experience, sparsHard: enrollment.sparsHard)

        let currentWeek: ConditioningProgramWeek?
        switch status {
        case .notStarted: currentWeek = weeks.first
        case .active(let week, _, _): currentWeek = weeks[week - 1]
        case .completed: currentWeek = nil
        }

        var progress: [ConditioningTargetProgress] = []
        var suggestion: ConditioningTodaySuggestion?
        if let currentWeek, case .active(_, _, let isPaused) = status {
            let startOfToday = calendar.startOfDay(for: now)
            let weekStart = ConditioningProgramSchedule
                .currentWeekStart(on: today, enrollment: enrollment, calendar: calendar)
                .startDate(in: calendar)
            let lacticWindowStart = now.addingTimeInterval(-ConditioningProgramCoach.lacticSpacing)
            let entries = conditioningRecords
                .fetch(since: min(weekStart, lacticWindowStart, startOfToday))
                .compactMap(Self.logEntry)
            let weekEntries = entries.filter { $0.startTime >= weekStart }
            progress = ConditioningProgramCoach.progress(for: currentWeek, weekEntries: weekEntries)

            if !isPaused {
                let strengthToday = workoutSessions.fetchCompletedSessions(since: startOfToday).compactMap(Self.strengthEntry)
                suggestion = ConditioningProgramCoach.suggestion(
                    week: currentWeek,
                    weekEntries: weekEntries,
                    recentEntries: entries.filter { $0.startTime >= min(lacticWindowStart, startOfToday) },
                    strengthToday: strengthToday,
                    sparsHard: enrollment.sparsHard,
                    now: now,
                    calendar: calendar
                )
            }
        }

        dashboard = ConditioningProgramDashboard(
            enrollment: enrollment,
            status: status,
            weeks: weeks,
            currentWeek: currentWeek,
            progress: progress,
            suggestion: suggestion
        )
    }

    private static func logEntry(_ record: ConditioningRecord) -> ConditioningLogEntry? {
        guard let energySystem = record.energySystem else { return nil }
        return ConditioningLogEntry(
            session: record.sessionType,
            energySystem: energySystem,
            startTime: record.startTime,
            endTime: record.endTime
        )
    }

    private static func strengthEntry(_ session: WorkoutSession) -> StrengthLogEntry? {
        guard let endTime = session.endTime else { return nil }
        let muscleGroups = (session.workoutExercises ?? []).map(\.muscleGroups)
        return StrengthLogEntry(
            endTime: endTime,
            isHeavyLowerBody: StrengthLogEntry.isHeavyLowerBody(exerciseMuscleGroups: muscleGroups)
        )
    }
}
