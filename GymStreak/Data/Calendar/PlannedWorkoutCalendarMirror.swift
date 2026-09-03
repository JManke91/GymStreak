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
/// Lives here rather than in a ViewModel because several unrelated surfaces need
/// exactly the same three steps — the routines list (via `RoutinesViewModel`),
/// the Settings toggle and the app becoming active — and none should own the
/// repositories-plus-gateway glue. Shaped like the other `Data/` coordinators
/// (`WatchWorkoutIngestionCoordinator`, `ExerciseCatalogSyncCoordinator`).
///
/// **The plan's anchor is computed, never stored.** Nothing here rolls a plan
/// forward: `WorkoutPlanningService.cadenceAnchor` re-derives it from the last
/// completed session on every call, so "trained two days late → the calendar
/// moves" is a pure recomputation of `desired` and the existing diff does the
/// rest (docs/calendar-sync.md §12).
@MainActor
final class PlannedWorkoutCalendarMirror: PlannedWorkoutCalendarMirroring {

    /// Same subsystem as the other export paths, so one Console filter shows a
    /// failed watch sync and a failed calendar write for the same launch.
    private static let logger = Logger(subsystem: LogSubsystem.sync, category: "CalendarMirror")

    private let routineRepository: RoutineRepository
    private let workoutSessionRepository: WorkoutSessionRepository
    private let preference: any CalendarSyncPreferenceProviding
    private let sync: any WorkoutCalendarSyncing

    /// What the last **successful** pass put in the calendar, and which calendar
    /// it was. Held only for this launch: a fresh launch always reconciles once,
    /// which is the cheapest way to recover from anything that happened while
    /// the app was not running.
    private var lastMirrored: MirroredState?

    /// The short-circuit's memory. Exact rather than a hash — a handful of
    /// occurrences per routine is small enough to keep verbatim, and a hash
    /// collision here would mean a calendar that silently stops updating.
    private struct MirroredState {
        let calendarIdentifier: String?
        let desired: PlannedWorkoutCalendarState
    }

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

    func reconcile(revalidatingCalendar: Bool) {
        // The opt-in is the whole gate. Nothing is read from the user's calendar
        // — not even to look — until they have switched sync on.
        guard preference.isCalendarSyncEnabled else {
            // Forgotten rather than kept, so switching sync back on writes a full
            // window into the fresh calendar instead of short-circuiting against
            // what the *old* one used to hold.
            lastMirrored = nil
            return
        }

        let routines = routineRepository.fetchAll()
        // The same bounded per-routine lookup the routines list uses, not a scan
        // of the whole completed history: this runs on every plan change and the
        // history grows forever while the routine list does not.
        //
        // This is also the whole of the drift handling. A workout finished late
        // lands here as a newer `lastCompleted`, `WorkoutPlanningService`
        // re-anchors the cadence on it, and the occurrences below simply come
        // out on different days.
        let lastCompleted = workoutSessionRepository.lastCompletedStartDates(
            forRoutineIds: routines.map(\.id)
        )
        let desired = PlannedWorkoutCalendarStateBuilder.state(
            routines: routines,
            lastCompleted: lastCompleted
        )

        // The short-circuit that keeps a frequently-fired hook honest: it runs
        // after every routines fetch, and `events(matching:)` hits a CalDAV-backed
        // store that Apple suggests not querying on the main thread at all. An
        // unchanged desired state performs **no** EventKit call. The calendar
        // identifier is part of the comparison so a recreated calendar — same
        // plans, empty calendar — is never mistaken for a no-op.
        //
        // A revalidating pass steps over it deliberately. Neither of the
        // take-it-away cases moves the app's desired state by one byte, so a pass
        // that trusted this cache could never discover them; that is the whole
        // reason the once-per-activation trigger exists.
        if !revalidatingCalendar,
           let lastMirrored,
           lastMirrored.calendarIdentifier == sync.appCalendarIdentifier,
           lastMirrored.desired == desired {
            return
        }

        do {
            try sync.mirror(desired)
            lastMirrored = MirroredState(
                calendarIdentifier: sync.appCalendarIdentifier,
                desired: desired
            )
        } catch WorkoutCalendarSyncError.calendarMissing {
            handleCalendarRemoved()
        } catch WorkoutCalendarSyncError.accessDenied {
            // Access was revoked in Settings while the app was away. Stop
            // writing and leave it there: the *intent* flag stays on, so
            // restoring access resumes the mirror without the user hunting for
            // the toggle again, and nothing re-prompts —
            // `requestFullAccessToEvents()` would not show anything anyway once
            // the user has decided. The Settings row reads the live status and
            // shows the way back (docs/calendar-sync.md §12).
            lastMirrored = nil
            Self.logger.info("Calendar mirror skipped: access is no longer granted")
        } catch {
            // Deliberately swallowed. The plan is already saved and correct; the
            // calendar is a projection of it, and a projection that failed to
            // update is not worth interrupting the user over. Nothing is
            // remembered about the failure beyond clearing the short-circuit, so
            // the next pass retries in full and reconciles from the calendar as
            // it actually is.
            lastMirrored = nil
            Self.logger.error("Calendar mirror failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The user deleted the app's calendar in Calendar.app, or removed the
    /// account it lived on.
    ///
    /// **Read as an opt-out.** Deleting a calendar is a deliberate act, so the
    /// toggle goes off and Settings shows that. The rejected alternative was to
    /// silently recreate it, which fights the user and would make the calendar
    /// impossible to get rid of without also finding the toggle. Re-enabling
    /// creates a fresh calendar and fills a full window.
    ///
    /// **The user's plan is untouched.** Only the projection goes away.
    private func handleCalendarRemoved() {
        // The calendar is already gone, so this only drops the stale identifier —
        // and it is what stops the next enable from stacking a second calendar
        // beside a handle that resolves to nothing. It can throw only when access
        // is not full, which the mirror above would have reported instead.
        try? sync.disable()
        preference.isCalendarSyncEnabled = false
        lastMirrored = nil
        Self.logger.info("Calendar mirror stopped: the app's calendar was deleted; sync switched off")
    }
}
