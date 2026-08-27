//
//  RoutineCapTests.swift
//  GymStreakTests
//
//  P1 — the three-routine cap (docs/monetization-strategy.md §4.2a, §4.4, §7).
//  The load-bearing assertion is the lapse case: a user who dropped from Pro
//  keeps every routine they made and can still train all of them. Rule 4 says
//  nothing is ever taken away, so only *creating another one* is blocked.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory
// ModelContainer creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct RoutineCapTests {

    private let limit = ProFeatureCaps.freeRoutineLimit

    // MARK: - Free, under and at the cap

    @Test("Under the cap, the create flow opens and no paywall is raised")
    func underCapCreatesNormally() {
        let harness = makeHarness()
        harness.fill(count: limit - 1)

        harness.viewModel.requestAddRoutine()

        #expect(harness.viewModel.isRoutineCapReached == false)
        #expect(harness.viewModel.showingAddRoutine)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("At the cap, creating raises the routineCap paywall instead")
    func atCapRaisesPaywall() {
        let harness = makeHarness()
        harness.fill(count: limit)

        harness.viewModel.requestAddRoutine()

        #expect(harness.viewModel.isRoutineCapReached)
        #expect(harness.viewModel.showingAddRoutine == false)
        #expect(harness.paywalls.presentedPlacements == [.routineCap])
        // The gate blocks, it never destroys.
        #expect(harness.viewModel.routines.count == limit)
    }

    @Test("Duplicating counts as creating and is gated the same way")
    func duplicateIsCapped() throws {
        let harness = makeHarness()
        harness.fill(count: limit)
        let source = try #require(harness.viewModel.routines.first)

        let copy = harness.viewModel.duplicateRoutine(source)

        #expect(copy == nil)
        #expect(harness.viewModel.routines.count == limit)
        #expect(harness.paywalls.presentedPlacements == [.routineCap])
    }

    @Test("Deleting back under the cap restores the ability to create")
    func deletingRestoresCreation() throws {
        let harness = makeHarness()
        harness.fill(count: limit)
        let routine = try #require(harness.viewModel.routines.first)

        harness.viewModel.deleteRoutine(routine)
        harness.viewModel.requestAddRoutine()

        #expect(harness.viewModel.isRoutineCapReached == false)
        #expect(harness.viewModel.showingAddRoutine)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - Lapse (§7, Rule 4)

    @Test("A lapsed user keeps every routine above the cap, fully intact")
    func lapsedUserKeepsRoutinesAboveTheCap() {
        // Built while Pro, then the entitlement drops away.
        let harness = makeHarness(state: .subscription)
        harness.fill(count: limit + 3)
        #expect(harness.viewModel.isRoutineCapReached == false)

        harness.entitlements.state = .free

        // Nothing is deleted, hidden or made read-only.
        #expect(harness.viewModel.routines.count == limit + 3)
        #expect(harness.viewModel.routines.allSatisfy { !$0.routineExercisesList.isEmpty })
        // ...and every one of them is still editable in place.
        let renamed = harness.viewModel.routines[limit + 2]
        renamed.name = "Edited after lapse"
        harness.viewModel.updateRoutine(renamed)
        #expect(harness.viewModel.routines.contains { $0.name == "Edited after lapse" })
    }

    @Test("A lapsed user above the cap is blocked only from creating another")
    func lapsedUserCannotCreateWhileOverTheCap() {
        let harness = makeHarness(state: .subscription)
        harness.fill(count: limit + 3)
        harness.entitlements.state = .free

        harness.viewModel.requestAddRoutine()

        #expect(harness.viewModel.isRoutineCapReached)
        #expect(harness.viewModel.showingAddRoutine == false)
        #expect(harness.paywalls.presentedPlacements == [.routineCap])
        #expect(harness.viewModel.routines.count == limit + 3)
    }

    @Test("Work already inside the create flow is never refused at save")
    func inFlightCreationIsNeverLost() {
        let harness = makeHarness()
        harness.fill(count: limit - 1)

        // The user opened the flow under the cap; a routine created elsewhere
        // (watch sync, iCloud) put them at it before they finished typing.
        harness.viewModel.requestAddRoutine()
        harness.fill(count: 1)
        harness.viewModel.createRoutine(name: "Finished in flight", pendingExercises: [])

        #expect(harness.viewModel.routines.contains { $0.name == "Finished in flight" })
    }

    // MARK: - Pro, Founder and the kill switch

    @Test("A Pro subscriber has no cap, no nudge and no gate", arguments: [
        ProEntitlementState.subscription, .lifetime, .founder
    ])
    func proAndFounderSeeNoCap(state: ProEntitlementState) {
        let harness = makeHarness(state: state)
        harness.fill(count: limit + 2)

        harness.viewModel.requestAddRoutine()

        #expect(harness.viewModel.isRoutineCapReached == false)
        #expect(harness.viewModel.routineCapNudge == nil)
        #expect(harness.viewModel.showingAddRoutine)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("With the kill switch off, behavior is identical to today")
    func killSwitchOffBehavesAsBefore() throws {
        let harness = makeHarness(isGatingEnabled: false)
        harness.fill(count: limit + 2)

        harness.viewModel.requestAddRoutine()
        let copy = harness.viewModel.duplicateRoutine(try #require(harness.viewModel.routines.first))

        #expect(harness.viewModel.isRoutineCapReached == false)
        #expect(harness.viewModel.routineCapNudge == nil)
        #expect(harness.viewModel.showingAddRoutine)
        #expect(copy != nil)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - Placement D — the nudge

    @Test("The nudge appears on the last free slot and stays at the cap")
    func nudgeAppearsOnTheLastFreeSlot() throws {
        let harness = makeHarness()

        harness.fill(count: limit - 2)
        #expect(harness.viewModel.routineCapNudge == nil)

        harness.fill(count: 1)
        let approaching = try #require(harness.viewModel.routineCapNudge)
        #expect(approaching.used == limit - 1)
        #expect(approaching.limit == limit)
        #expect(approaching.text.contains("\(limit - 1)"))
        #expect(approaching.text.contains("\(limit)"))

        harness.fill(count: 1)
        let reached = try #require(harness.viewModel.routineCapNudge)
        #expect(reached.used == limit)
        // Number-free at and above the cap: a lapsed user can be at 6 of 3.
        #expect(reached.text == "routines.cap.nudge.reached".localized)
        #expect(reached.text != "routines.cap.nudge.reached")
    }

    @Test("The nudge tracks a lapse without a refetch")
    func nudgeFollowsTheEntitlement() {
        let harness = makeHarness(state: .subscription)
        harness.fill(count: limit - 1)

        #expect(harness.viewModel.routineCapNudge == nil)

        harness.entitlements.state = .free

        #expect(harness.viewModel.routineCapNudge != nil)
    }

    // MARK: - The policy, without a container
    //
    // §4.4 expects the cap to be retuned (a 3-vs-4 A/B test) post-launch, so the
    // boundary math is asserted against an explicit `limit` as well as against
    // the shipped constant.

    @Test("The cap is reached at the limit, never before it", arguments: [3, 4])
    func policyBoundary(limit: Int) {
        func isReached(_ count: Int) -> Bool {
            RoutineCapPolicy.isCapReached(
                routineCount: count, isPro: false, isGatingEnabled: true, limit: limit
            )
        }

        #expect(isReached(limit - 1) == false)
        #expect(isReached(limit))
        #expect(isReached(limit + 5))
    }

    @Test("The nudge starts on the last free slot and never stops above the cap")
    func policyNudgeStates() {
        func state(_ count: Int) -> RoutineCapPolicy.NudgeState? {
            RoutineCapPolicy.nudgeState(
                routineCount: count, isPro: false, isGatingEnabled: true, limit: 3
            )
        }

        #expect(state(1) == nil)
        #expect(state(2) == .approaching(used: 2, limit: 3))
        #expect(state(3) == .reached(used: 3, limit: 3))
        // A lapsed user really is at 6 of 3; the state carries the true count.
        #expect(state(6) == .reached(used: 6, limit: 3))
    }

    @Test("Pro and the kill switch each exempt a user from the policy entirely")
    func policyExemptions() {
        #expect(RoutineCapPolicy.isCapReached(
            routineCount: 99, isPro: true, isGatingEnabled: true
        ) == false)
        #expect(RoutineCapPolicy.isCapReached(
            routineCount: 99, isPro: false, isGatingEnabled: false
        ) == false)
        #expect(RoutineCapPolicy.nudgeState(
            routineCount: 99, isPro: true, isGatingEnabled: true
        ) == nil)
        #expect(RoutineCapPolicy.nudgeState(
            routineCount: 99, isPro: false, isGatingEnabled: false
        ) == nil)
    }

    // MARK: - The built-in example routine (docs/example-starter-routine.md)
    //
    // We put it there, so it never eats a free slot the user could have used.
    // Shipping it without this exclusion would have turned "3 free routines"
    // into 2 for every new free user — a gate tightening arriving as a side
    // effect of an onboarding feature (§10).

    @Test("The example routine leaves all three free slots for the user's own")
    func exampleRoutineDoesNotConsumeAFreeSlot() {
        let harness = makeHarness()
        harness.seedExampleRoutine()

        harness.fill(count: limit - 1)
        #expect(harness.viewModel.isRoutineCapReached == false)

        harness.fill(count: 1)

        // Three of their own saved, and only now does the gate close.
        #expect(harness.viewModel.isRoutineCapReached)
        #expect(harness.viewModel.countableRoutineCount == limit)
        #expect(harness.viewModel.routines.count == limit + 1)
    }

    @Test("The nudge counts the user's own routines, not ours")
    func nudgeIgnoresTheExampleRoutine() throws {
        let harness = makeHarness()
        harness.seedExampleRoutine()

        // One routine in the list, none of them the user's: silence.
        #expect(harness.viewModel.routineCapNudge == nil)

        harness.fill(count: limit - 2)
        #expect(harness.viewModel.routineCapNudge == nil)

        harness.fill(count: 1)
        let approaching = try #require(harness.viewModel.routineCapNudge)
        #expect(approaching.used == limit - 1)

        harness.fill(count: 1)
        let reached = try #require(harness.viewModel.routineCapNudge)
        #expect(reached.used == limit)
    }

    @Test("Editing or renaming the example routine keeps it off the cap")
    func editingTheExampleRoutineChangesNothing() {
        let harness = makeHarness()
        let seeded = harness.seedExampleRoutine()

        seeded.name = "My Monday session"
        harness.viewModel.updateRoutine(seeded)
        harness.fill(count: limit - 1)

        // The rule is permanent: `seedKey` survives the edit, so the routine
        // stays outside the count rather than starting to charge the user for
        // engaging with the very thing it is teaching.
        #expect(harness.viewModel.isRoutineCapReached == false)
        #expect(harness.viewModel.countableRoutineCount == limit - 1)
        harness.viewModel.requestAddRoutine()
        #expect(harness.viewModel.showingAddRoutine)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Deleting the example routine leaves the allowance exactly as it was")
    func deletingTheExampleRoutineChangesNothing() {
        let harness = makeHarness()
        let seeded = harness.seedExampleRoutine()
        harness.fill(count: limit - 1)

        harness.viewModel.deleteRoutine(seeded)

        #expect(harness.viewModel.countableRoutineCount == limit - 1)
        #expect(harness.viewModel.isRoutineCapReached == false)

        harness.fill(count: 1)
        #expect(harness.viewModel.isRoutineCapReached)
    }

    @Test("A duplicate of the example routine is the user's own, and counts")
    func duplicatingTheExampleRoutineCounts() throws {
        let harness = makeHarness()
        let seeded = harness.seedExampleRoutine()

        let copy = try #require(harness.viewModel.duplicateRoutine(seeded))

        #expect(copy.seedKey.isEmpty)
        #expect(harness.viewModel.countableRoutineCount == 1)
    }

    @Test("A lapsed user above the cap is unaffected by a seeded routine")
    func lapsedUserWithSeededRoutineStaysBlocked() {
        let harness = makeHarness(state: .subscription)
        harness.seedExampleRoutine()
        harness.fill(count: limit + 3)
        harness.entitlements.state = .free

        harness.viewModel.requestAddRoutine()

        #expect(harness.viewModel.isRoutineCapReached)
        #expect(harness.viewModel.showingAddRoutine == false)
        // The count they are shown is their own, not inflated by ours.
        #expect(harness.viewModel.countableRoutineCount == limit + 3)
        #expect(harness.viewModel.routineCapNudge?.used == limit + 3)
        #expect(harness.viewModel.routines.count == limit + 4)
    }

    @Test("The counting rule, at the policy boundary")
    func policyCountingRule() {
        let own = Routine(name: "Mine")
        let seeded = Routine(name: "Ours")
        seeded.seedKey = SeedRoutineCatalog.entries[0].seedKey

        #expect(RoutineCapPolicy.countsTowardCap(own))
        #expect(RoutineCapPolicy.countsTowardCap(seeded) == false)
        #expect(RoutineCapPolicy.countableRoutineCount(in: []) == 0)
        #expect(RoutineCapPolicy.countableRoutineCount(in: [seeded]) == 0)
        #expect(RoutineCapPolicy.countableRoutineCount(in: [seeded, own, seeded]) == 1)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let viewModel: RoutinesViewModel
        let entitlements: StubProEntitlements
        let paywalls: RecordingPaywallPresenter
        let context: ModelContext

        /// Puts the built-in example routine in the store, the way
        /// `ExampleRoutineSeeder` does — a routine like any other, marked by a
        /// non-empty `seedKey`.
        @discardableResult
        func seedExampleRoutine() -> Routine {
            let seeded = Routine(name: "Example routine")
            seeded.seedKey = SeedRoutineCatalog.entries[0].seedKey
            context.insert(seeded)
            try? context.save()
            viewModel.fetchRoutines()
            return seeded
        }

        /// Saves `count` further routine templates, bypassing the entry point —
        /// this is the state a user arrives in, not the thing under test.
        func fill(count: Int) {
            let existing = viewModel.routines.count
            for index in 0..<count {
                viewModel.createRoutine(
                    name: "Routine \(existing + index)",
                    pendingExercises: [PendingRoutineExercise(
                        exercise: Exercise(name: "Exercise \(existing + index)"),
                        sets: [ExerciseSet(reps: 8, weight: 50, restTime: 90, order: 0)],
                        order: 0,
                        alternatives: []
                    )]
                )
            }
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
        return Harness(
            viewModel: viewModel,
            entitlements: entitlements,
            paywalls: paywalls,
            context: context
        )
    }
}
