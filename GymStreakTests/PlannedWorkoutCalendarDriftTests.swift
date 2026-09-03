//
//  PlannedWorkoutCalendarDriftTests.swift
//  GymStreakTests
//
//  Ticket 03: the mirror follows the plan. Training late re-anchors the cadence
//  and the calendar's future days move with it, the rolling window tops itself
//  up, an unchanged desired state costs no EventKit call at all, and the two
//  ways the user can take the feature away behind the app's back are handled
//  without ever touching their plan.
//
//  The gateway is a fake throughout, so no `EKEventStore` is constructed.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct PlannedWorkoutCalendarDriftTests {

    // MARK: - Harness

    private struct Harness {
        let context: ModelContext
        let preference: CalendarSyncPreference
        let sync: FakeWorkoutCalendarSync
        let mirror: PlannedWorkoutCalendarMirror
        let viewModel: RoutinesViewModel

        /// Lets the reconcile `fetchRoutines()` defers into its own main-actor
        /// turn run — it is deliberately off the routines list's critical path.
        /// Three, not one: a notification-driven refresh costs a hop to the main
        /// actor, then the coalescing slot's own hop, then the reconcile the
        /// refresh defers — and each is a separate turn.
        func settle() async {
            await Task.yield()
            await Task.yield()
            await Task.yield()
        }

        @discardableResult
        func makeRoutine(
            named name: String,
            intervalDays: Int,
            startDate: Date
        ) -> Routine {
            let routine = Routine(name: name)
            context.insert(routine)
            let schedule = RoutineSchedule(
                type: .everyNDays,
                intervalDays: intervalDays,
                weekdays: [],
                startDate: startDate
            )
            schedule.isActive = true
            schedule.routine = routine
            context.insert(schedule)
            return routine
        }

        /// A finished workout, which is the only thing that moves a cadence
        /// anchor. Nothing writes an anchor anywhere — the plan keeps its
        /// reference date and the anchor is recomputed from this.
        func completeWorkout(for routine: Routine, on day: Date) {
            let session = WorkoutSession(routine: routine)
            session.startTime = day
            session.endTime = day.addingTimeInterval(3600)
            context.insert(session)
            try? context.save()
        }
    }

    private static func throwawayDefaults() -> UserDefaults {
        let suiteName = "test.calendar_drift.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    private func makeHarness() -> Harness {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let preference = CalendarSyncPreference(defaults: Self.throwawayDefaults())
        preference.isCalendarSyncEnabled = true
        let sync = FakeWorkoutCalendarSync()
        sync.accessStatus = .fullAccess
        sync.appCalendarIdentifier = "test-calendar"
        let mirror = PlannedWorkoutCalendarMirror(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository,
            preference: preference,
            sync: sync
        )
        let viewModel = RoutinesViewModel(
            routineRepository: routineRepository,
            workoutSessionRepository: sessionRepository,
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .subscription),
            paywalls: RecordingPaywallPresenter(),
            calendarMirror: mirror,
            isGatingEnabled: false
        )
        return Harness(
            context: context,
            preference: preference,
            sync: sync,
            mirror: mirror,
            viewModel: viewModel
        )
    }

    private static func day(_ offsetFromToday: Int) -> Date {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offsetFromToday, to: today) ?? today
    }

    // MARK: - Drift: the Things note's "due Tuesday, trained Thursday" case

    @Test("Training late moves the future occurrences with it, without touching the plan")
    func lateCompletionReanchorsTheCalendar() throws {
        let harness = makeHarness()
        // The Things note's case. Planned every 7 days from 10 days ago, so the
        // session was due 3 days ago and the calendar's next day is today + 4.
        let routine = harness.makeRoutine(
            named: "Push", intervalDays: 7, startDate: Self.day(-10)
        )

        harness.mirror.reconcile()
        let beforeDrift = try #require(harness.sync.mirroredOccurrences.last)
        #expect(beforeDrift.map(\.day) == (0..<8).map { Self.day(4 + $0 * 7) })

        // The user misses that day and trains two days late instead — yesterday.
        harness.completeWorkout(for: routine, on: Self.day(-1))
        harness.mirror.reconcile()

        let afterDrift = try #require(harness.sync.mirroredOccurrences.last)
        // The whole series re-anchors on the completion: +6, +13, …, and the
        // stale +4 is no longer wanted.
        #expect(afterDrift.map(\.day) == (0..<8).map { Self.day(6 + $0 * 7) })
        #expect(!afterDrift.map(\.day).contains(Self.day(4)))
        // Nothing was rolled forward: the plan still carries the reference date
        // the user chose, and the anchor is recomputed from history every pass.
        #expect(routine.schedule?.startDate == Self.day(-10))
    }

    @Test("The stale days are deleted and the re-anchored ones created")
    func driftProducesTheExpectedActions() {
        // End-to-end through the pure reconciler: what the calendar already holds
        // is the pre-drift batch, what the plan now wants is the post-drift one.
        let routineId = UUID()
        func occurrence(_ offset: Int) -> PlannedWorkoutOccurrence {
            PlannedWorkoutOccurrence(
                routineId: routineId, day: Self.day(offset), title: "Push Workout"
            )
        }
        // Written before the drift: +4, +11, +18.
        let existing = [4, 11, 18].map(occurrence).enumerated().map {
            MirroredWorkoutEvent(reference: $0.offset, markerURL: $0.element.marker)
        }
        // Wanted after training two days late: +6, +13, +20.
        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: PlannedWorkoutCalendarState(occurrences: [6, 13, 20].map(occurrence)),
            existing: existing
        )

        // Every stale day goes and every new day is written — an anchor shift is
        // just "different desired dates" to the diff, which is why the mirror
        // never has to edit into an existing recurring series.
        #expect(Array(actions.prefix(3)) == [
            .delete(reference: 0), .delete(reference: 1), .delete(reference: 2)
        ])
        let created = actions.compactMap { action -> Date? in
            if case .create(let occurrence) = action { return occurrence.day }
            return nil
        }
        #expect(created == [Self.day(6), Self.day(13), Self.day(20)])
    }

    @Test("A workout ingested from the watch drifts the calendar the same way")
    func watchIngestedCompletionReanchorsTheCalendar() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(
            named: "Push", intervalDays: 5, startDate: Self.day(-5)
        )
        harness.mirror.reconcile()

        // No separate code path, and no watch file is touched: the watch's
        // ingestion posts `.workoutHistoryDidChange`, and the routines refresh
        // that triggers is what reconciles.
        harness.completeWorkout(for: routine, on: Self.day(-1))
        NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
        await harness.settle()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.map(\.day) == (0..<8).map { Self.day(4 + $0 * 5) })
    }

    @Test("A burst of history notifications collapses into one correct refresh")
    func burstOfNotificationsStillEndsInTheRightState() async throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine(
            named: "Push", intervalDays: 5, startDate: Self.day(-5)
        )
        harness.mirror.reconcile()

        // The watch drain posts once per inbox entry, so a queue of three
        // workouts fans out three notifications in the same main-actor turn.
        // They coalesce — and the surviving refresh must still see the newest
        // completion, not a stale one.
        //
        // This guards "nothing is dropped", which is the property that can break
        // correctness; it does not prove the collapse itself, since three
        // uncoalesced refreshes would short-circuit inside the mirror and leave
        // the same end state. Proving the collapse would need a counting spy on
        // the repository, which is not worth a test double for an optimisation.
        harness.completeWorkout(for: routine, on: Self.day(-1))
        for _ in 0..<3 {
            NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
        }
        await harness.settle()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.map(\.day) == (0..<8).map { Self.day(4 + $0 * 5) })
    }

    // MARK: - Window top-up

    @Test("Successive completions keep a full horizon, with no gap and no duplicates")
    func windowTopsItselfUp() throws {
        let harness = makeHarness()
        let interval = 3
        let routine = harness.makeRoutine(
            named: "Push", intervalDays: interval, startDate: Self.day(-30)
        )
        let horizon = PlannedWorkoutCalendarStateBuilder.horizonPerRoutine
        let calendar = HistoryStatsService.isoGermanCalendar()

        // Four sessions across the last month. After each one the mirror is asked
        // again — as a completion, a foreground or a routines refresh would.
        for completion in [-24, -18, -11, -4] {
            harness.completeWorkout(for: routine, on: Self.day(completion))
            harness.mirror.reconcile()

            let days = try #require(harness.sync.mirroredOccurrences.last).map(\.day)
            // A full horizon every time — the window tops itself up rather than
            // draining as days pass.
            #expect(days.count == horizon)
            // No duplicates, nothing in the past, and no gap: consecutive days are
            // exactly one interval apart.
            #expect(Set(days).count == horizon)
            #expect(days.allSatisfy { $0 >= Self.day(0) })
            #expect(zip(days, days.dropFirst()).allSatisfy {
                calendar.dateComponents([.day], from: $0, to: $1).day == interval
            })
        }
    }

    @Test("The window starts today, so days already past are never diffed")
    func pastDaysAreOutsideTheWindow() {
        let occurrence = PlannedWorkoutOccurrence(
            routineId: UUID(), day: Self.day(30), title: "Push Workout"
        )
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(
            desired: PlannedWorkoutCalendarState(occurrences: [occurrence])
        )

        #expect(window.firstDay == Self.day(0))
        #expect(!window.covers(startOfDay: Self.day(-1)))
        #expect(window.covers(startOfDay: Self.day(0)))
    }

    // MARK: - The digest short-circuit

    @Test("An unchanged desired state performs no calendar call at all")
    func unchangedStateSkipsTheGateway() {
        let harness = makeHarness()
        harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))

        harness.mirror.reconcile()
        #expect(harness.sync.mirroredOccurrences.count == 1)

        // The hook fires after every routines refresh; without the short-circuit
        // each one would be a CalDAV round-trip.
        harness.mirror.reconcile()
        harness.mirror.reconcile()
        #expect(harness.sync.mirroredOccurrences.count == 1)
    }

    @Test("A revalidating pass steps over the short-circuit on purpose")
    func revalidatingPassAlwaysReachesTheCalendar() {
        let harness = makeHarness()
        harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()

        // Nothing about the plan changed, and that is exactly the case a deleted
        // calendar or a revoked permission presents — so the once-per-activation
        // pass has to reach the calendar anyway.
        harness.mirror.reconcile(revalidatingCalendar: true)

        #expect(harness.sync.mirroredOccurrences.count == 2)
    }

    @Test("A changed plan gets through the short-circuit")
    func changedStateReachesTheGateway() {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()

        harness.completeWorkout(for: routine, on: Self.day(0))
        harness.mirror.reconcile()

        #expect(harness.sync.mirroredOccurrences.count == 2)
    }

    @Test("A recreated calendar is refilled, never mistaken for a no-op")
    func recreatedCalendarIsRefilled() {
        let harness = makeHarness()
        harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()

        // Same plans, same occurrences — but a different, empty calendar. The
        // identifier is part of what the short-circuit compares precisely so
        // this writes rather than skips.
        harness.sync.appCalendarIdentifier = "a-different-calendar"
        harness.mirror.reconcile()

        #expect(harness.sync.mirroredOccurrences.count == 2)
    }

    // MARK: - When the user takes the calendar away

    @Test("Deleting the app's calendar switches sync off and leaves the plan alone")
    func deletedCalendarIsReadAsAnOptOut() {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()

        // The user deletes "Gym Streak" in Calendar.app. Nothing tells the app;
        // the identifier it holds simply stops resolving, and the plan has not
        // moved — so only a revalidating pass (the app becoming active) can find
        // it, which is precisely why that trigger exists.
        harness.sync.isCalendarMissing = true
        harness.mirror.reconcile(revalidatingCalendar: true)

        #expect(harness.preference.isCalendarSyncEnabled == false)
        // The stale handle is dropped, so re-enabling builds a fresh calendar
        // instead of stacking a second one beside a dead identifier.
        #expect(harness.sync.appCalendarIdentifier == nil)
        // The plan is the source of truth and is untouched.
        #expect(routine.schedule?.isActive == true)
        #expect(routine.schedule?.intervalDays == 4)
    }

    @Test("A further pass after the deletion writes nothing and does not fail repeatedly")
    func deletedCalendarStopsFurtherPasses() {
        let harness = makeHarness()
        harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()
        let writesBefore = harness.sync.mirroredOccurrences.count

        harness.sync.isCalendarMissing = true
        harness.mirror.reconcile(revalidatingCalendar: true)
        harness.mirror.reconcile(revalidatingCalendar: true)
        harness.mirror.reconcile()

        // The opt-in is off now, so every later pass returns at the gate.
        #expect(harness.sync.mirroredOccurrences.count == writesBefore)
    }

    @Test("Re-enabling after a deletion produces a fresh calendar and a full window")
    func reEnablingAfterDeletionRefillsTheWindow() async throws {
        let harness = makeHarness()
        harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()
        harness.sync.isCalendarMissing = true
        harness.mirror.reconcile(revalidatingCalendar: true)

        let settings = CalendarSyncSettingsViewModel(
            preference: harness.preference,
            sync: harness.sync,
            mirror: harness.mirror
        )
        await settings.setEnabled(true)

        #expect(harness.preference.isCalendarSyncEnabled)
        #expect(harness.sync.appCalendarIdentifier != nil)
        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
    }

    // MARK: - When the user takes access away

    @Test("Revoked access stops the writes and keeps the user's intent and plan")
    func revokedAccessStopsWritingWithoutLosingIntent() {
        let harness = makeHarness()
        let routine = harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()
        let writesBefore = harness.sync.mirroredOccurrences.count

        // Revoked in Settings while the app was away. The plan has not moved, so
        // the app becoming active is what finds it; a later completion tries
        // again and is refused just the same.
        harness.sync.accessStatus = .denied
        harness.mirror.reconcile(revalidatingCalendar: true)
        harness.completeWorkout(for: routine, on: Self.day(0))
        harness.mirror.reconcile()

        #expect(harness.sync.mirroredOccurrences.count == writesBefore)
        // Intent stays on: restoring access resumes the mirror by itself, with no
        // second trip to the toggle and no prompt.
        #expect(harness.preference.isCalendarSyncEnabled)
        #expect(harness.sync.enableCallCount == 0)
        #expect(routine.schedule?.isActive == true)
    }

    @Test("Restoring access resumes the mirror on the next pass")
    func restoredAccessResumesTheMirror() throws {
        let harness = makeHarness()
        harness.makeRoutine(named: "Push", intervalDays: 4, startDate: Self.day(0))
        harness.mirror.reconcile()
        harness.sync.accessStatus = .denied
        harness.mirror.reconcile(revalidatingCalendar: true)

        harness.sync.accessStatus = .fullAccess
        harness.mirror.reconcile()

        let batch = try #require(harness.sync.mirroredOccurrences.last)
        #expect(batch.count == PlannedWorkoutCalendarStateBuilder.horizonPerRoutine)
    }

    @Test("Settings shows the way back when access was revoked out of band")
    func settingsRowReflectsRevokedAccess() {
        let harness = makeHarness()
        let settings = CalendarSyncSettingsViewModel(
            preference: harness.preference,
            sync: harness.sync,
            mirror: harness.mirror
        )

        settings.refreshStatus()
        #expect(settings.failure == nil)

        harness.sync.accessStatus = .denied
        settings.refreshStatus()
        #expect(settings.failure == .accessDenied)
        // The toggle still reads on — the user's intent has not changed, only
        // the permission — and nothing re-prompted.
        #expect(settings.isEnabled)
        #expect(harness.sync.enableCallCount == 0)

        harness.sync.accessStatus = .fullAccess
        settings.refreshStatus()
        #expect(settings.failure == nil)
    }
}
