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
    /// Also `nil` while `isLocked` — a locked week hands out nothing to start.
    let suggestion: ConditioningTodaySuggestion?
    /// The P12 depth gate's answer for the week in progress, as it stood when
    /// this dashboard was built (ticket 08).
    ///
    /// `progress` stays **fully populated** while locked, deliberately: the gate
    /// blurs the user's own plan rather than hiding it (§3 Rule 2), so the view
    /// needs the real targets to render behind the lock. What the lock withholds
    /// is everything actionable — today's suggestion, the watch offer and the
    /// post-workout add-on all go silent, which is why each of them consults
    /// this rather than the entitlement.
    let isLocked: Bool
    /// `true` in the last free week: §8 placement D's non-blocking "Phase 2
    /// starts next week" hint, shown *before* the wall rather than at it.
    let isLastFreeWeek: Bool
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
    /// The P12 depth gate (ticket 08). `nil` in tests that are not about
    /// gating — the program then behaves exactly as it did before the gate,
    /// which is also what `ProGating.isEnabled == false` produces.
    @ObservationIgnored private let gate: ConditioningProgramGate?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(
        store: any ConditioningProgramStoring,
        conditioningRecords: any ConditioningRecordRepository,
        workoutSessions: any WorkoutSessionRepository,
        watch: (any ConditioningWatchPublishing)? = nil,
        heartRateProfiles: (any HeartRateProfileStoring)? = nil,
        gate: ConditioningProgramGate? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.conditioningRecords = conditioningRecords
        self.workoutSessions = workoutSessions
        self.watch = watch
        self.heartRateProfiles = heartRateProfiles
        self.gate = gate
        self.calendar = calendar
        self.now = now
        // A purchase, a lapse or a restore has to move more than the blur: the
        // suggestion, the watch offer and the add-on are all computed in
        // `refresh()` from the entitlement as it stood then.
        gate?.observeEntitlementChanges { [weak self] in self?.refresh() }
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

    // MARK: - P12 depth gate (ticket 08)

    /// Whether the week in progress is behind the Pro gate, answered **live**.
    ///
    /// Read from `body`, not from `dashboard.isLocked`, on purpose: the gate
    /// reads the entitlement inside this call and SwiftUI tracks that read
    /// transitively, so a completed purchase unblurs the plan on the spot
    /// instead of at the next `refresh()`. `dashboard.isLocked` is the same
    /// answer frozen at refresh time, for the consumers that have no `body`.
    var isProgramLocked: Bool { gate?.isLocked(week: dashboard?.currentWeek?.number) ?? false }

    /// The gate's one intent point. Nothing auto-presents — §8 requires a tap.
    func requestProgramUnlock() {
        gate?.requestUnlock()
    }

    /// How many program weeks a free user gets — the nudge's denominator.
    var freeProgramWeeks: Int { gate?.freeWeeks ?? ProFeatureCaps.freeConditioningProgramWeeks }

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

        // The gate is evaluated once here and carried on the dashboard, so the
        // watch offer and the add-on read one answer rather than each asking the
        // entitlement — and so a locked week cannot hand out a session through a
        // path somebody forgot to gate.
        let isLocked = gate?.isLocked(week: currentWeek?.number) ?? false

        var progress: [ConditioningTargetProgress] = []
        var suggestion: ConditioningTodaySuggestion?
        if let currentWeek, case .active(_, _, let isPaused) = status {
            let entries = coachEntries(enrollment: enrollment, today: today, now: now)
            progress = ConditioningProgramCoach.progress(for: currentWeek, weekEntries: entries.week)

            if !isPaused, !isLocked {
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
            suggestion: suggestion,
            isLocked: isLocked,
            isLastFreeWeek: isLastFreeWeek(status: status)
        )
    }

    /// §8 placement D's cue. Unlike the blur it is not read live in `body` — the
    /// entitlement observer refreshes on a purchase, and a hint that is one
    /// render late costs nothing.
    private func isLastFreeWeek(status: ConditioningProgramStatus) -> Bool {
        guard case .active(let week, _, _) = status else { return false }
        return gate?.isLastFreeWeek(week: week) ?? false
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
              !isPaused,
              // A locked week prescribes nothing, so there is nothing to add on
              // after a workout either (ticket 08).
              gate?.isLocked(week: weekNumber) != true else { return .none }

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
