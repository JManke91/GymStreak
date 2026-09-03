//
//  PlannedWorkoutCalendarMirror.swift
//  GymStreak
//
//  The glue between "a plan changed" and "the calendar now shows it": reads the
//  current plans, asks the Domain builder what the calendar should hold, and
//  hands the result to the EventKit gateway. Imports no EventKit itself — the
//  gateway is behind `WorkoutCalendarSyncing`.
//  See docs/calendar-sync.md.
//

import Foundation
import OSLog

/// Reconciles the app-owned calendar with the user's current plans.
///
/// Lives here rather than in a ViewModel because two unrelated surfaces need
/// exactly the same three steps — the planning sheet (via `RoutinesViewModel`)
/// and the Settings toggle — and neither should own the repositories-plus-gateway
/// glue. Shaped like the other `Data/` coordinators
/// (`WatchWorkoutIngestionCoordinator`, `ExerciseCatalogSyncCoordinator`).
@MainActor
final class PlannedWorkoutCalendarMirror: PlannedWorkoutCalendarMirroring {

    /// Same subsystem as the other export paths, so one Console filter shows a
    /// failed watch sync and a failed calendar write for the same launch.
    private static let logger = Logger(subsystem: LogSubsystem.sync, category: "CalendarMirror")

    private let routineRepository: RoutineRepository
    private let workoutSessionRepository: WorkoutSessionRepository
    private let preference: any CalendarSyncPreferenceProviding
    private let sync: any WorkoutCalendarSyncing

    init(
        routineRepository: RoutineRepository,
        workoutSessionRepository: WorkoutSessionRepository,
        preference: any CalendarSyncPreferenceProviding,
        sync: any WorkoutCalendarSyncing
    ) {
        self.routineRepository = routineRepository
        self.workoutSessionRepository = workoutSessionRepository
        self.preference = preference
        self.sync = sync
    }

    func reconcile() {
        // The opt-in is the whole gate. Nothing is read from the user's calendar
        // — not even to look — until they have switched sync on.
        guard preference.isCalendarSyncEnabled else { return }

        let routines = routineRepository.fetchAll()
        // The same bounded per-routine lookup the routines list uses, not a scan
        // of the whole completed history: this runs on every plan change and the
        // history grows forever while the routine list does not.
        let lastCompleted = workoutSessionRepository.lastCompletedStartDates(
            forRoutineIds: routines.map(\.id)
        )
        let occurrences = PlannedWorkoutOccurrenceBuilder.occurrences(
            routines: routines,
            lastCompleted: lastCompleted
        )

        do {
            try sync.mirror(occurrences: occurrences)
        } catch {
            // Deliberately swallowed. The plan is already saved and correct; the
            // calendar is a projection of it, and a projection that failed to
            // update is not worth interrupting the user over. The next plan
            // change — or ticket 03's refresh — reconciles from the calendar as
            // it actually is, so nothing has to be remembered about the failure.
            Self.logger.error("Calendar mirror failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
