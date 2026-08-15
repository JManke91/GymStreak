//
//  ScheduleGatingTests.swift
//  GymStreakTests
//
//  P9 — fixed-weekday schedules are Pro (docs/monetization-strategy.md §4.2a,
//  §7). The load-bearing assertions are the lapse ones: a weekday plan built
//  while subscribed keeps driving the planned week, the weekly goal and the
//  next-due ordering forever, and a refused edit leaves it byte-for-byte intact.
//  Only *writing* a weekday shape is ever blocked.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory
// ModelContainer creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct ScheduleGatingTests {

    // MARK: - Free: the cadence is free, the weekly split is not

    @Test("A free user plans the rolling cadence with no gate at all")
    func freeUserPlansCadence() throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine()

        let saved = harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 3, weekdays: [], referenceDate: .now
        )

        #expect(saved)
        let schedule = try #require(routine.schedule)
        #expect(schedule.type == .everyNDays)
        #expect(schedule.intervalDays == 3)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Choosing the weekday mode raises the weekdaySchedule placement")
    func weekdayModeRaisesPaywall() {
        let harness = makeHarness()

        let allowed = harness.viewModel.requestWeekdaySchedule()

        #expect(allowed == false)
        #expect(harness.viewModel.isWeekdayScheduleLocked)
        #expect(harness.paywalls.presentedPlacements == [.weekdaySchedule])
    }

    @Test("Saving a weekday plan is refused and writes nothing")
    func weekdaySaveIsRefused() {
        let harness = makeHarness()
        let routine = harness.makeRoutine()

        let saved = harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 3, 5], referenceDate: .now
        )

        #expect(saved == false)
        // Refused *before* any mutation — the routine is left unplanned rather
        // than planned in a shape it may not have.
        #expect(routine.schedule == nil)
        #expect(harness.paywalls.presentedPlacements == [.weekdaySchedule])
    }

    @Test("Switching an existing cadence plan into weekday shape is refused, cadence intact")
    func switchingIntoWeekdayShapeIsRefused() throws {
        let harness = makeHarness()
        let routine = harness.makeRoutine()
        harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 4, weekdays: [], referenceDate: .now
        )
        harness.paywalls.reset()

        let saved = harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 4, weekdays: [2, 4], referenceDate: .now
        )

        #expect(saved == false)
        let schedule = try #require(routine.schedule)
        #expect(schedule.type == .everyNDays)
        #expect(schedule.intervalDays == 4)
        #expect(schedule.weekdays.isEmpty)
        #expect(harness.paywalls.presentedPlacements == [.weekdaySchedule])
    }

    // MARK: - Lapse (§7, Rule 4) — the schedule the user already built

    @Test("A weekday plan built while subscribed keeps driving the planned week after a lapse")
    func lapsedWeekdayPlanStillPlansTheWeek() throws {
        let harness = makeHarness(state: .subscription)
        let routine = harness.makeRoutine()
        // Every weekday, so the assertion holds whichever day the suite runs on.
        let everyDay = Set(1...7)
        #expect(harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: everyDay, referenceDate: .now
        ))

        harness.entitlements.state = .free

        let schedule = try #require(routine.schedule)
        #expect(schedule.type == .weekdays)
        #expect(schedule.weekdays == everyDay)
        // The planner is entitlement-unaware: it still counts all seven days.
        let planned = WorkoutPlanningService.plannedWeek(
            routines: harness.viewModel.routines, completedSessions: []
        )
        #expect(planned.goal == 7)
        #expect(planned.plannedDates.count == 7)
        // ...and next-due still resolves, so up-next ordering is unaffected.
        #expect(harness.viewModel.nextDueDate(for: routine) != nil)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("A refused edit of an existing weekday plan leaves it intact")
    func refusedEditLeavesExistingPlanIntact() throws {
        let harness = makeHarness(state: .subscription)
        let routine = harness.makeRoutine()
        harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 3, 5], referenceDate: .now
        )
        harness.entitlements.state = .free
        harness.paywalls.reset()

        // The user re-opens the sheet and tries to add Sunday.
        let saved = harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 3, 5, 7], referenceDate: .now
        )

        #expect(saved == false)
        let schedule = try #require(routine.schedule)
        #expect(schedule.weekdays == [1, 3, 5])
        #expect(schedule.isActive)
        #expect(harness.paywalls.presentedPlacements == [.weekdaySchedule])
    }

    @Test("A lapsed user may move an existing weekday plan back to the free cadence")
    func lapsedUserMayLeaveWeekdayShape() throws {
        let harness = makeHarness(state: .subscription)
        let routine = harness.makeRoutine()
        harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 3, 5], referenceDate: .now
        )
        harness.entitlements.state = .free

        let saved = harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 5, weekdays: [1, 3, 5], referenceDate: .now
        )

        #expect(saved)
        let schedule = try #require(routine.schedule)
        #expect(schedule.type == .everyNDays)
        #expect(schedule.intervalDays == 5)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Removing a plan works in every entitlement state", arguments: [
        ProEntitlementState.free, .subscription, .lifetime, .founder
    ])
    func removingIsNeverGated(state: ProEntitlementState) {
        // Built while Pro so the weekday shape exists even for the free case.
        let harness = makeHarness(state: .subscription)
        let routine = harness.makeRoutine()
        harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 3, 5], referenceDate: .now
        )
        harness.entitlements.state = state
        harness.paywalls.reset()

        harness.viewModel.removeSchedule(from: routine)

        #expect(routine.schedule == nil)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - Pro, Founder and the kill switch

    @Test("A Pro subscriber and a Founder see no gate", arguments: [
        ProEntitlementState.subscription, .lifetime, .founder
    ])
    func proAndFounderSeeNoGate(state: ProEntitlementState) throws {
        let harness = makeHarness(state: state)
        let routine = harness.makeRoutine()

        #expect(harness.viewModel.isWeekdayScheduleLocked == false)
        #expect(harness.viewModel.requestWeekdaySchedule())
        #expect(harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [2, 5], referenceDate: .now
        ))
        #expect(try #require(routine.schedule).weekdays == [2, 5])
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("With the kill switch off, scheduling behaves identically to today")
    func killSwitchOffBehavesAsBefore() throws {
        let harness = makeHarness(isGatingEnabled: false)
        let routine = harness.makeRoutine()

        #expect(harness.viewModel.isWeekdayScheduleLocked == false)
        #expect(harness.viewModel.requestWeekdaySchedule())
        #expect(harness.viewModel.setSchedule(
            for: routine, type: .weekdays, intervalDays: 3, weekdays: [1, 4], referenceDate: .now
        ))
        #expect(try #require(routine.schedule).weekdays == [1, 4])
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - The policy, on its own

    @Test("Only the weekday shape is ever locked, and only for a gated user")
    func policyLocksWeekdaysOnly() {
        #expect(ScheduleGatingPolicy.isScheduleTypeLocked(
            .weekdays, isPro: false, isGatingEnabled: true
        ))
        #expect(ScheduleGatingPolicy.isScheduleTypeLocked(
            .everyNDays, isPro: false, isGatingEnabled: true
        ) == false)
    }

    @Test("Pro and the kill switch each exempt a user from the policy entirely")
    func policyExemptions() {
        #expect(ScheduleGatingPolicy.isScheduleTypeLocked(
            .weekdays, isPro: true, isGatingEnabled: true
        ) == false)
        #expect(ScheduleGatingPolicy.isScheduleTypeLocked(
            .weekdays, isPro: false, isGatingEnabled: false
        ) == false)
        #expect(ScheduleGatingPolicy.isSubjectToGate(isPro: false, isGatingEnabled: true))
        #expect(ScheduleGatingPolicy.isSubjectToGate(isPro: true, isGatingEnabled: true) == false)
        #expect(ScheduleGatingPolicy.isSubjectToGate(isPro: false, isGatingEnabled: false) == false)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let viewModel: RoutinesViewModel
        let entitlements: StubProEntitlements
        let paywalls: RecordingPaywallPresenter

        /// A saved routine to plan. Creation is capped by P1, not by P9, so it
        /// goes through the ViewModel exactly as the create flow does.
        func makeRoutine() -> Routine {
            let name = "Routine \(viewModel.routines.count)"
            viewModel.createRoutine(name: name, pendingExercises: [])
            // Looked up by name rather than by position: the repository sorts
            // `updatedAt`-descending, which is not creation order.
            return viewModel.routines.first { $0.name == name }!
        }
    }

    /// Defaults to gating **on**, unlike the shipped app: with the real
    /// `ProGating.isEnabled` every one of these would pass for the wrong reason.
    private func makeHarness(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true
    ) -> Harness {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let entitlements = StubProEntitlements(state: state)
        let paywalls = RecordingPaywallPresenter()
        let viewModel = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: entitlements,
            paywalls: paywalls,
            isGatingEnabled: isGatingEnabled
        )
        return Harness(viewModel: viewModel, entitlements: entitlements, paywalls: paywalls)
    }
}
