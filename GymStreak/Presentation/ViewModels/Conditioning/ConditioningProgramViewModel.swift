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
    /// Receives the week's open sessions after every `refresh()` (ticket 06). `nil` in
    /// tests that do not care about the watch.
    @ObservationIgnored private let watch: (any ConditioningWatchPublishing)?
    @ObservationIgnored private let heartRateProfiles: (any HeartRateProfileStoring)?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(
        store: any ConditioningProgramStoring,
        conditioningRecords: any ConditioningRecordRepository,
        workoutSessions: any WorkoutSessionRepository,
        watch: (any ConditioningWatchPublishing)? = nil,
        heartRateProfiles: (any HeartRateProfileStoring)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.conditioningRecords = conditioningRecords
        self.workoutSessions = workoutSessions
        self.watch = watch
        self.heartRateProfiles = heartRateProfiles
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
    /// Also republishes the watch offer, which is idempotent when nothing changed.
    func refresh() {
        defer { watch?.publishConditioningOffer(watchOffer()) }
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
            let entries = coachEntries(enrollment: enrollment, today: today, now: now)
            progress = ConditioningProgramCoach.progress(for: currentWeek, weekEntries: entries.week)

            if !isPaused {
                let startOfToday = calendar.startOfDay(for: now)
                let strengthToday = workoutSessions.fetchCompletedSessions(since: startOfToday).compactMap(Self.strengthEntry)
                suggestion = ConditioningProgramCoach.suggestion(
                    week: currentWeek,
                    weekEntries: entries.week,
                    recentEntries: entries.recent,
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

    /// The sessions the watch offers (ticket 06), derived from `dashboard` so the watch
    /// never disagrees with the Conditioning screen. See `ConditioningProgramViewModel+WatchOffer`.
    func watchOffer() -> ConditioningWatchOffer {
        Self.watchOffer(
            dashboard: dashboard,
            today: today,
            profile: heartRateProfiles?.heartRateProfile,
            calendar: calendar,
            now: now()
        )
    }

    /// The post-workout add-on offer for a strength workout that has **just**
    /// finished on this phone (docs/fight-conditioning.md, ticket 05).
    ///
    /// The workout is handed in rather than fetched: the summary screen shows
    /// this before the user taps Save, so the session the offer is about is not
    /// in the repository yet. It is appended to today's committed workouts, so
    /// the coach's own leg-day and spacing rules see it.
    ///
    /// Reads nothing this type does not already read in `refresh()`, and writes
    /// nothing — the dashboard is untouched.
    func addOn(finishedAt: Date, isHeavyLowerBody: Bool) -> ConditioningAddOnOffer {
        guard let enrollment = store.enrollment else { return .none }
        let now = now()
        let today = ConditioningProgramDay(now, calendar: calendar)
        guard case .active(let weekNumber, _, let isPaused) = ConditioningProgramSchedule
            .status(on: today, enrollment: enrollment, calendar: calendar),
              !isPaused else { return .none }

        let weeks = ConditioningProgramContent.weeks(experience: enrollment.experience, sparsHard: enrollment.sparsHard)
        guard weeks.indices.contains(weekNumber - 1) else { return .none }
        let currentWeek = weeks[weekNumber - 1]

        let entries = coachEntries(enrollment: enrollment, today: today, now: now)
        var strengthToday = workoutSessions
            .fetchCompletedSessions(since: calendar.startOfDay(for: now))
            .compactMap(Self.strengthEntry)
        strengthToday.append(StrengthLogEntry(endTime: finishedAt, isHeavyLowerBody: isHeavyLowerBody))

        return ConditioningProgramCoach.addOn(
            week: currentWeek,
            weekEntries: entries.week,
            recentEntries: entries.recent,
            strengthToday: strengthToday,
            sparsHard: enrollment.sparsHard,
            finishedAt: finishedAt,
            now: now,
            calendar: calendar
        )
    }

    /// The conditioning history the coach needs, in one bounded fetch: this
    /// program week's entries, plus the last 48 h for the lactic-spacing rule —
    /// which can reach back into the previous week.
    private func coachEntries(
        enrollment: ConditioningProgramEnrollment,
        today: ConditioningProgramDay,
        now: Date
    ) -> (week: [ConditioningLogEntry], recent: [ConditioningLogEntry]) {
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = ConditioningProgramSchedule
            .currentWeekStart(on: today, enrollment: enrollment, calendar: calendar)
            .startDate(in: calendar)
        let lacticWindowStart = now.addingTimeInterval(-ConditioningProgramCoach.lacticSpacing)
        let entries = conditioningRecords
            .fetch(since: min(weekStart, lacticWindowStart, startOfToday))
            .compactMap(Self.logEntry)
        return (
            week: entries.filter { $0.startTime >= weekStart },
            recent: entries.filter { $0.startTime >= min(lacticWindowStart, startOfToday) }
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
        return strengthEntry(session, endTime: endTime)
    }

    /// Classifies one workout for the coach's spacing rules.
    ///
    /// **The single definition of "heavy lower body" for this feature**, so the
    /// dashboard and the post-workout add-on can never disagree about a session.
    /// `endTime` is supplied rather than read off the model because the add-on
    /// classifies a workout the summary screen has not committed yet.
    /// `WorkoutExercise.muscleGroups` is a stored `[String]`, so this walk faults
    /// nothing.
    static func strengthEntry(_ session: WorkoutSession, endTime: Date) -> StrengthLogEntry {
        StrengthLogEntry(
            endTime: endTime,
            isHeavyLowerBody: StrengthLogEntry.isHeavyLowerBody(
                exerciseMuscleGroups: (session.workoutExercises ?? []).map(\.muscleGroups)
            )
        )
    }
}
