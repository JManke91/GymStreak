//
//  RoutinePlanDuplicateTests.swift
//  GymStreakTests
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// A duplicate plan is structurally reachable now that `Routine.schedules` is a
// to-many: two devices planning offline, or two repair passes racing, can leave
// a second row. `Routine.schedule` hides the loser, which is exactly what makes
// a half-deletion dangerous — the loser gets promoted and the plan comes back.
@Suite(.serialized)
@MainActor
struct RoutinePlanDuplicateTests {

    @Test("Removing a plan deletes every row, so no duplicate is promoted")
    func removingAPlanDeletesDuplicates() throws {
        let harness = makeHarness()
        let routine = harness.makeRoutineWithDuplicatePlans()
        #expect(routine.schedules?.count == 2)

        harness.viewModel.removeSchedule(from: routine)

        #expect(routine.schedule == nil)
        #expect(routine.schedules?.isEmpty ?? true)
    }

    @Test("Editing a plan collapses the duplicate instead of leaving it behind")
    func editingAPlanCollapsesDuplicates() throws {
        let harness = makeHarness()
        let routine = harness.makeRoutineWithDuplicatePlans()

        let saved = harness.viewModel.setSchedule(
            for: routine, type: .everyNDays, intervalDays: 9, weekdays: [], referenceDate: .now
        )

        #expect(saved)
        #expect(routine.schedules?.count == 1)
        #expect(try #require(routine.schedule).intervalDays == 9)
    }

    // MARK: - Harness

    private struct Harness {
        let context: ModelContext
        let viewModel: RoutinesViewModel

        /// Two plans on one routine, distinguishable by `createdAt` so
        /// `Routine.schedule` picks a stable winner.
        func makeRoutineWithDuplicatePlans() -> Routine {
            let routine = Routine(name: "Push")
            context.insert(routine)
            for offset in [0.0, 60.0] {
                let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 5)
                schedule.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + offset)
                schedule.routine = routine
                context.insert(schedule)
            }
            return routine
        }
    }

    private func makeHarness() -> Harness {
        let context = ModelContext(InMemoryModelContainer.make())
        return Harness(
            context: context,
            viewModel: RoutinesViewModel(
                routineRepository: SwiftDataRoutineRepository(modelContext: context),
                workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
                watchSync: MockWatchSyncServicing(),
                proEntitlements: StubProEntitlements(state: .subscription),
                paywalls: RecordingPaywallPresenter(),
                isGatingEnabled: false
            )
        )
    }
}
