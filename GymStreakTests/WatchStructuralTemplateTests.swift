//
//  WatchStructuralTemplateTests.swift
//  GymStreakTests
//
//  Ticket 07 (in-workout routine editing): persisting watch add/remove edits
//  into the routine. Covers three seams:
//    • wire backward-compat + membership mapping (`CompletedWatchWorkout` →
//      `IncomingWatchWorkout`);
//    • the watch optimistic fold's structural add/remove/superset behavior
//      (`WatchRoutineTemplateFold`), reached through the iOS-target copy;
//    • the iOS authoritative structural merge (`WatchTemplateTransactionService`)
//      over an isolated one-save transaction.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - Wire backward-compat + membership mapping

@Suite(.serialized)
@MainActor
struct WatchStructuralWireTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func legacyPayloadWithoutStructuralKeysDecodesWithNilArrays() throws {
        // Simulates a pre-ticket-07 watch payload: the new keys are absent.
        let workoutId = UUID()
        let routineId = UUID()
        let json = """
        {
          "id": "\(workoutId.uuidString)",
          "routineId": "\(routineId.uuidString)",
          "routineName": "Push Day",
          "startTime": 0,
          "endTime": 600,
          "exercises": [],
          "shouldUpdateTemplate": true
        }
        """
        let decoded = try JSONDecoder().decode(CompletedWatchWorkout.self, from: Data(json.utf8))
        #expect(decoded.addedRoutineExerciseIDs == nil)
        #expect(decoded.removedRoutineExerciseIDs == nil)

        // The Data→Domain mapper normalizes absence to empty.
        let incoming = decoded.toIncomingWatchWorkout()
        #expect(incoming.addedRoutineExerciseIDs.isEmpty)
        #expect(incoming.removedRoutineExerciseIDs.isEmpty)
    }

    @Test
    func membershipIntentAndSeedKeyRoundTripThroughMapper() throws {
        let added = UUID()
        let removed = UUID()
        var completed = Fixtures.makeExercise(id: added, sets: [Fixtures.makeSet()])
        completed.exerciseSeedKey = "seed.bench_press"
        var workout = Fixtures.makeWorkout(shouldUpdateTemplate: true, exercises: [completed])
        workout.addedRoutineExerciseIDs = [added]
        workout.removedRoutineExerciseIDs = [removed]

        // Round-trips through Codable unchanged.
        let reencoded = try JSONDecoder().decode(
            CompletedWatchWorkout.self, from: JSONEncoder().encode(workout)
        )
        #expect(reencoded.addedRoutineExerciseIDs == [added])
        #expect(reencoded.removedRoutineExerciseIDs == [removed])
        #expect(reencoded.exercises.first?.exerciseSeedKey == "seed.bench_press")

        let incoming = workout.toIncomingWatchWorkout()
        #expect(incoming.addedRoutineExerciseIDs == [added])
        #expect(incoming.removedRoutineExerciseIDs == [removed])
        #expect(incoming.exercises.first?.exerciseSeedKey == "seed.bench_press")
    }
}

// MARK: - Watch optimistic fold (structural)

@Suite(.serialized)
@MainActor
struct WatchStructuralFoldTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private func watchExercise(
        _ id: UUID, order: Int, supersetId: UUID? = nil, supersetOrder: Int = 0,
        setId: UUID = UUID(), reps: Int = 10
    ) -> WatchExercise {
        WatchExercise(
            id: id, name: "Ex", muscleGroup: "Chest",
            sets: [WatchSet(id: setId, reps: reps, weight: 40, restTime: 60)],
            order: order, supersetId: supersetId, supersetOrder: supersetOrder
        )
    }

    private func addedWorkout(
        routineId: UUID, finalExercises: [CompletedWatchExercise], added: [UUID] = [], removed: [UUID] = []
    ) -> CompletedWatchWorkout {
        var w = Fixtures.makeWorkout(routineId: routineId, shouldUpdateTemplate: true, exercises: finalExercises)
        w.addedRoutineExerciseIDs = added
        w.removedRoutineExerciseIDs = removed
        return w
    }

    @Test
    func addAppendsPendingSlotPreservingMintedIdentitiesAndSeedKey() {
        let routineId = UUID()
        let a = UUID(), aSet = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [
            watchExercise(a, order: 0, setId: aSet)
        ])

        let newSlot = UUID(), newSet = UUID(), libID = UUID()
        var addedEx = Fixtures.makeExercise(
            id: newSlot, exerciseId: libID, name: "Curl",
            sets: [Fixtures.makeSet(id: newSet, plannedReps: 8, actualReps: 8, plannedWeight: 20, actualWeight: 20)]
        )
        addedEx.exerciseSeedKey = "seed.curl"
        // Final state carries the retained A (unchanged) plus the new slot.
        let retainedA = Fixtures.makeExercise(
            id: a, name: "Ex",
            sets: [Fixtures.makeSet(id: aSet, plannedReps: 10, actualReps: 10, plannedWeight: 40, actualWeight: 40)]
        )
        let workout = addedWorkout(routineId: routineId, finalExercises: [retainedA, addedEx], added: [newSlot])

        let result = WatchRoutineTemplateFold.apply(workout, to: base)

        #expect(result.exercises.count == 2)
        #expect(result.exercises.map(\.order) == [0, 1])
        let appended = result.exercises[1]
        #expect(appended.id == newSlot)
        #expect(appended.isPendingWatchAddition == true)
        #expect(appended.exerciseId == libID)
        #expect(appended.exerciseSeedKey == "seed.curl")
        #expect(appended.sets.map(\.id) == [newSet])
        #expect(appended.sets.first?.reps == 8)
        #expect(appended.sets.first?.weight == 20)
        // The retained slot stays authoritative (not flagged pending).
        #expect(result.exercises[0].id == a)
        #expect(result.exercises[0].isPendingWatchAddition != true)
    }

    @Test
    func removeDeletesSlotAndNormalizesOrder() {
        let routineId = UUID()
        let a = UUID(), b = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [
            watchExercise(a, order: 0), watchExercise(b, order: 1)
        ])
        // Final state kept only B; A was removed.
        let retainedB = Fixtures.makeExercise(id: b, name: "Ex", sets: [Fixtures.makeSet()])
        let workout = addedWorkout(routineId: routineId, finalExercises: [retainedB], removed: [a])

        let result = WatchRoutineTemplateFold.apply(workout, to: base)
        #expect(result.exercises.map(\.id) == [b])
        #expect(result.exercises.map(\.order) == [0])
    }

    @Test
    func removingTwoMemberSupersetClearsSurvivor() {
        let routineId = UUID()
        let a = UUID(), b = UUID(), group = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [
            watchExercise(a, order: 0, supersetId: group, supersetOrder: 0),
            watchExercise(b, order: 1, supersetId: group, supersetOrder: 1)
        ])
        let retainedB = Fixtures.makeExercise(id: b, name: "Ex", sets: [Fixtures.makeSet()])
        let workout = addedWorkout(routineId: routineId, finalExercises: [retainedB], removed: [a])

        let result = WatchRoutineTemplateFold.apply(workout, to: base)
        let survivor = try! #require(result.exercises.first { $0.id == b })
        #expect(survivor.supersetId == nil)
        #expect(survivor.supersetOrder == 0)
    }

    @Test
    func removingFromThreeMemberSupersetRenumbersSurvivors() {
        let routineId = UUID()
        let a = UUID(), b = UUID(), c = UUID(), group = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [
            watchExercise(a, order: 0, supersetId: group, supersetOrder: 0),
            watchExercise(b, order: 1, supersetId: group, supersetOrder: 1),
            watchExercise(c, order: 2, supersetId: group, supersetOrder: 2)
        ])
        // Remove the middle member B.
        let ra = Fixtures.makeExercise(id: a, name: "Ex", sets: [Fixtures.makeSet()])
        let rc = Fixtures.makeExercise(id: c, name: "Ex", sets: [Fixtures.makeSet()])
        let workout = addedWorkout(routineId: routineId, finalExercises: [ra, rc], removed: [b])

        let result = WatchRoutineTemplateFold.apply(workout, to: base)
        let survivors = result.exercises.filter { $0.supersetId == group }
        #expect(survivors.count == 2)
        #expect(Set(survivors.map(\.supersetOrder)) == [0, 1])
    }

    @Test
    func foldIsIdempotentForAdditions() {
        let routineId = UUID()
        let a = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [watchExercise(a, order: 0)])
        let newSlot = UUID()
        let addedEx = Fixtures.makeExercise(id: newSlot, name: "Curl", sets: [Fixtures.makeSet()])
        let retainedA = Fixtures.makeExercise(id: a, name: "Ex", sets: [Fixtures.makeSet()])
        let workout = addedWorkout(routineId: routineId, finalExercises: [retainedA, addedEx], added: [newSlot])

        let once = WatchRoutineTemplateFold.apply(workout, to: base)
        let twice = WatchRoutineTemplateFold.apply(workout, to: once)
        #expect(twice.exercises.map(\.id) == once.exercises.map(\.id))
        #expect(twice.exercises.filter { $0.id == newSlot }.count == 1)
    }

    @Test
    func effectiveRoutinesShowsPendingAdditionAsOverlay() throws {
        let store = WatchSyncStateStore(directory: try Fixtures.makeTempDirectory())
        let routineId = UUID()
        let a = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [watchExercise(a, order: 0)])
        store.applyRoutineContext([base], header: nil)

        let newSlot = UUID()
        let addedEx = Fixtures.makeExercise(id: newSlot, name: "Curl", sets: [Fixtures.makeSet()])
        let retainedA = Fixtures.makeExercise(id: a, name: "Ex", sets: [Fixtures.makeSet()])
        let workout = addedWorkout(routineId: routineId, finalExercises: [retainedA, addedEx], added: [newSlot])
        _ = try store.enqueue(workout, phase: .transportEligible, routineAnchor: base)

        let effective = try #require(store.effectiveRoutines().first { $0.id == routineId })
        #expect(effective.exercises.count == 2)
        let appended = try #require(effective.exercises.first { $0.id == newSlot })
        #expect(appended.isPendingWatchAddition == true)
    }

    @Test
    func setOnlyFoldIsUnchangedWithoutStructuralIntent() {
        let routineId = UUID()
        let a = UUID(), aSet = UUID()
        let base = WatchRoutine(id: routineId, name: "Push", exercises: [
            watchExercise(a, order: 0, setId: aSet, reps: 10)
        ])
        // A set edit only (actual != planned), no structural intent.
        let edited = Fixtures.makeExercise(
            id: a, name: "Ex",
            sets: [Fixtures.makeSet(id: aSet, plannedReps: 10, actualReps: 12, plannedWeight: 40, actualWeight: 40)]
        )
        let workout = addedWorkout(routineId: routineId, finalExercises: [edited])

        let result = WatchRoutineTemplateFold.apply(workout, to: base)
        #expect(result.exercises.count == 1)
        #expect(result.exercises[0].id == a)
        #expect(result.exercises[0].order == 0)
        #expect(result.exercises[0].sets.first?.reps == 12)
    }
}

// MARK: - iOS authoritative structural merge

@Suite(.serialized)
@MainActor
struct WatchStructuralMergeTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext

        func makeService() -> (service: WatchTemplateTransactionService, tx: WorkoutHistoryTransaction) {
            let tx = SwiftDataWorkoutHistoryTransactionFactory(container: container).makeIsolatedTransaction()
            let service = WatchTemplateTransactionService(
                routineRepository: tx.routineRepository,
                workoutSessionRepository: tx.workoutSessionRepository,
                exerciseRepository: tx.exerciseRepository
            )
            return (service, tx)
        }

        /// Reads the committed routine through a fresh context, matching the
        /// authoritative post-commit production read.
        func committedRoutine(_ id: UUID) throws -> Routine {
            let fresh = ModelContext(container)
            return try #require(SwiftDataRoutineRepository(modelContext: fresh).fetch(id: id))
        }

        func committedSessions() -> [WorkoutSession] {
            let fresh = ModelContext(container)
            return SwiftDataWorkoutSessionRepository(modelContext: fresh).fetchAll()
        }
    }

    private func makeEnv() -> Env {
        let container = InMemoryModelContainer.make()
        return Env(container: container, context: container.mainContext)
    }

    @discardableResult
    private func insertExercise(
        _ env: Env, name: String, seedKey: String = "", createdAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> Exercise {
        let exercise = Exercise(name: name)
        exercise.seedKey = seedKey
        exercise.createdAt = createdAt
        env.context.insert(exercise)
        return exercise
    }

    /// Seeds a routine with the given library exercises as slots.
    @discardableResult
    private func seedRoutine(
        _ env: Env, name: String = "Push Day", exercises: [Exercise]
    ) throws -> Routine {
        let routine = Routine(name: name)
        for (order, exercise) in exercises.enumerated() {
            let slot = RoutineExercise(exercise: exercise, order: order)
            slot.routine = routine
            let set = ExerciseSet(reps: 10, weight: 60, restTime: 60, order: 0)
            set.routineExercise = slot
            slot.sets?.append(set)
            routine.routineExercises?.append(slot)
        }
        env.context.insert(routine)
        try env.context.save()
        return routine
    }

    private func completedExercise(
        slotID: UUID, exerciseId: UUID?, seedKey: String? = nil, name: String = "Ex",
        supersetId: UUID? = nil, supersetOrder: Int = 0, order: Int = 0,
        sets: [CompletedWatchSet]
    ) -> CompletedWatchExercise {
        CompletedWatchExercise(
            id: slotID, name: name, muscleGroup: "Chest", sets: sets, order: order,
            supersetId: supersetId, supersetOrder: supersetOrder,
            exerciseId: exerciseId, exerciseSeedKey: seedKey
        )
    }

    private func workout(
        routineId: UUID, exercises: [CompletedWatchExercise], added: [UUID] = [], removed: [UUID] = []
    ) -> IncomingWatchWorkout {
        var w = Fixtures.makeWorkout(
            routineId: routineId, shouldUpdateTemplate: true, exercises: exercises,
            transactionID: UUID(), senderEpoch: UUID(), sequence: 0
        )
        w.addedRoutineExerciseIDs = added
        w.removedRoutineExerciseIDs = removed
        return w.toIncomingWatchWorkout()
    }

    @Test
    func addResolvesByUUIDAndAppendsSlotWithMintedIdentities() throws {
        let env = makeEnv()
        let benchLib = insertExercise(env, name: "Bench Press")
        let curlLib = insertExercise(env, name: "Curl")
        let routine = try seedRoutine(env, exercises: [benchLib])
        let existingSlot = try #require(routine.routineExercisesList.first)

        let newSlot = UUID(), newSet = UUID()
        let retained = completedExercise(
            slotID: existingSlot.id, exerciseId: benchLib.id,
            sets: [Fixtures.makeSet(id: existingSlot.setsList.first!.id)]
        )
        let added = completedExercise(
            slotID: newSlot, exerciseId: curlLib.id, name: "Curl", order: 1,
            sets: [Fixtures.makeSet(id: newSet, plannedReps: 8, actualReps: 8, plannedWeight: 25, actualWeight: 25)]
        )
        let incoming = workout(routineId: routine.id, exercises: [retained, added], added: [newSlot])

        let (service, _) = env.makeService()
        guard case .applied = service.execute(incoming) else {
            Issue.record("Expected applied outcome"); return
        }

        let committed = try env.committedRoutine(routine.id)
        let slots = committed.routineExercisesList.sorted { $0.order < $1.order }
        #expect(slots.count == 2)
        #expect(slots.map(\.order) == [0, 1])
        let appended = slots[1]
        #expect(appended.id == newSlot)
        #expect(appended.exercise?.id == curlLib.id)
        #expect(appended.setsList.map(\.id) == [newSet])
        #expect(appended.setsList.first?.reps == 8)
        #expect(appended.setsList.first?.weight == 25)
        #expect(appended.supersetId == nil)
    }

    @Test
    func addFallsBackToDeterministicSeedKeySurvivorWhenUUIDMissing() throws {
        let env = makeEnv()
        // Two library rows share a seed key; the older createdAt is the survivor.
        let survivor = insertExercise(
            env, name: "Row", seedKey: "seed.row", createdAt: Date(timeIntervalSince1970: 1_000)
        )
        insertExercise(env, name: "Row", seedKey: "seed.row", createdAt: Date(timeIntervalSince1970: 5_000))
        let bench = insertExercise(env, name: "Bench Press")
        let routine = try seedRoutine(env, exercises: [bench])
        let existingSlot = try #require(routine.routineExercisesList.first)

        let newSlot = UUID()
        let retained = completedExercise(
            slotID: existingSlot.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: existingSlot.setsList.first!.id)]
        )
        // Watch-added exercise references a UUID that no longer resolves, only a seed key.
        let added = completedExercise(
            slotID: newSlot, exerciseId: UUID(), seedKey: "seed.row", name: "Row", order: 1,
            sets: [Fixtures.makeSet(id: UUID())]
        )
        let incoming = workout(routineId: routine.id, exercises: [retained, added], added: [newSlot])

        let (service, _) = env.makeService()
        guard case .applied = service.execute(incoming) else {
            Issue.record("Expected applied outcome"); return
        }

        let committed = try env.committedRoutine(routine.id)
        let appended = try #require(committed.routineExercisesList.first { $0.id == newSlot })
        #expect(appended.exercise?.id == survivor.id)
    }

    @Test
    func unresolvableAddedExerciseRejectsWholeRequestButSavesHistory() throws {
        let env = makeEnv()
        let bench = insertExercise(env, name: "Bench Press")
        let routine = try seedRoutine(env, exercises: [bench])
        let existingSlot = try #require(routine.routineExercisesList.first)

        let newSlot = UUID()
        let retained = completedExercise(
            slotID: existingSlot.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: existingSlot.setsList.first!.id)]
        )
        // Neither the UUID nor a seed key resolves to any library row.
        let added = completedExercise(
            slotID: newSlot, exerciseId: UUID(), seedKey: nil, name: "Ghost", order: 1,
            sets: [Fixtures.makeSet(id: UUID())]
        )
        let incoming = workout(routineId: routine.id, exercises: [retained, added], added: [newSlot])

        let (service, _) = env.makeService()
        guard case .rejected = service.execute(incoming) else {
            Issue.record("Expected rejected outcome"); return
        }

        // Routine untouched; the optimistic Watch slot is not persisted.
        let committed = try env.committedRoutine(routine.id)
        #expect(committed.routineExercisesList.count == 1)
        #expect(committed.routineExercisesList.first?.id == existingSlot.id)
        // History is still saved on a rejection.
        let sessions = env.committedSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.didUpdateTemplate == false)
    }

    @Test
    func removeDeletesSlotAndChildSets() throws {
        let env = makeEnv()
        let bench = insertExercise(env, name: "Bench Press")
        let curl = insertExercise(env, name: "Curl")
        let routine = try seedRoutine(env, exercises: [bench, curl])
        let slots = routine.routineExercisesList.sorted { $0.order < $1.order }
        let keep = slots[0], remove = slots[1]

        let retained = completedExercise(
            slotID: keep.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: keep.setsList.first!.id)]
        )
        let incoming = workout(routineId: routine.id, exercises: [retained], removed: [remove.id])

        let (service, _) = env.makeService()
        guard case .applied = service.execute(incoming) else {
            Issue.record("Expected applied outcome"); return
        }

        let committed = try env.committedRoutine(routine.id)
        #expect(committed.routineExercisesList.map(\.id) == [keep.id])
        #expect(committed.routineExercisesList.first?.order == 0)
        // The removed slot's sets are gone too.
        let fresh = ModelContext(env.container)
        let allSets = (try? fresh.fetch(FetchDescriptor<ExerciseSet>())) ?? []
        #expect(allSets.allSatisfy { $0.routineExercise?.id == keep.id })
    }

    @Test
    func concurrentlyDeletedRetainedSlotIsNoOpNotReAdded() throws {
        let env = makeEnv()
        let bench = insertExercise(env, name: "Bench Press")
        // iOS routine has ONLY bench; the watch's other slot was deleted on iOS.
        let routine = try seedRoutine(env, exercises: [bench])
        let keep = try #require(routine.routineExercisesList.first)

        let deletedSlotID = UUID()
        let retained = completedExercise(
            slotID: keep.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: keep.setsList.first!.id)]
        )
        // A retained slot the watch edited (modified set) but iOS deleted.
        let concurrentlyDeleted = completedExercise(
            slotID: deletedSlotID, exerciseId: UUID(), name: "Gone", order: 1,
            sets: [Fixtures.makeSet(id: UUID(), plannedReps: 10, actualReps: 15, plannedWeight: 40, actualWeight: 40)]
        )
        // Not in added / removed — a retained slot, present in final.
        let incoming = workout(routineId: routine.id, exercises: [retained, concurrentlyDeleted])

        let (service, _) = env.makeService()
        guard case .applied = service.execute(incoming) else {
            Issue.record("Expected applied outcome (no-op for deleted slot)"); return
        }

        let committed = try env.committedRoutine(routine.id)
        #expect(committed.routineExercisesList.map(\.id) == [keep.id])
        #expect(!committed.routineExercisesList.contains { $0.id == deletedSlotID })
    }

    @Test
    func malformedMembershipIntentRejectsWholly() throws {
        let env = makeEnv()
        let bench = insertExercise(env, name: "Bench Press")
        let routine = try seedRoutine(env, exercises: [bench])
        let slot = try #require(routine.routineExercisesList.first)

        let retained = completedExercise(
            slotID: slot.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: slot.setsList.first!.id)]
        )
        // A removed ID that is ALSO present in the final exercises is malformed.
        let incoming = workout(routineId: routine.id, exercises: [retained], removed: [slot.id])

        let (service, _) = env.makeService()
        guard case .rejected = service.execute(incoming) else {
            Issue.record("Expected rejected outcome for malformed intent"); return
        }
        let committed = try env.committedRoutine(routine.id)
        #expect(committed.routineExercisesList.count == 1)
    }

    @Test
    func removingTwoMemberSupersetClearsSurvivorOnIOS() throws {
        let env = makeEnv()
        let a = insertExercise(env, name: "A")
        let b = insertExercise(env, name: "B")
        let routine = try seedRoutine(env, exercises: [a, b])
        let slots = routine.routineExercisesList.sorted { $0.order < $1.order }
        let group = UUID()
        slots[0].supersetId = group; slots[0].supersetOrder = 0
        slots[1].supersetId = group; slots[1].supersetOrder = 1
        try env.context.save()

        let survivorSlot = slots[1]
        let retained = completedExercise(
            slotID: survivorSlot.id, exerciseId: b.id,
            sets: [Fixtures.makeSet(id: survivorSlot.setsList.first!.id)]
        )
        let incoming = workout(routineId: routine.id, exercises: [retained], removed: [slots[0].id])

        let (service, _) = env.makeService()
        guard case .applied = service.execute(incoming) else {
            Issue.record("Expected applied outcome"); return
        }

        let committed = try env.committedRoutine(routine.id)
        let survivor = try #require(committed.routineExercisesList.first { $0.id == survivorSlot.id })
        #expect(survivor.supersetId == nil)
        #expect(survivor.supersetOrder == 0)
    }

    @Test
    func concurrentIOSSlotIsPreservedThroughStructuralMerge() throws {
        let env = makeEnv()
        let bench = insertExercise(env, name: "Bench Press")
        let concurrent = insertExercise(env, name: "Concurrent iOS Add")
        let curl = insertExercise(env, name: "Curl")
        // Routine has bench + a slot iOS added concurrently that the watch never saw.
        let routine = try seedRoutine(env, exercises: [bench, concurrent])
        let benchSlot = try #require(routine.routineExercisesList.first { $0.exercise?.id == bench.id })
        let concurrentSlot = try #require(routine.routineExercisesList.first { $0.exercise?.id == concurrent.id })

        let newSlot = UUID()
        let retained = completedExercise(
            slotID: benchSlot.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: benchSlot.setsList.first!.id)]
        )
        let added = completedExercise(
            slotID: newSlot, exerciseId: curl.id, name: "Curl", order: 1,
            sets: [Fixtures.makeSet(id: UUID())]
        )
        // The watch never knew about `concurrentSlot`, so it is neither in the
        // payload nor removed — it must be preserved.
        let incoming = workout(routineId: routine.id, exercises: [retained, added], added: [newSlot])

        let (service, _) = env.makeService()
        guard case .applied = service.execute(incoming) else {
            Issue.record("Expected applied outcome"); return
        }

        let committed = try env.committedRoutine(routine.id)
        let ids = Set(committed.routineExercisesList.map(\.id))
        #expect(ids.contains(concurrentSlot.id))
        #expect(ids.contains(benchSlot.id))
        #expect(ids.contains(newSlot))
        #expect(committed.routineExercisesList.count == 3)
    }

    @Test
    func duplicateExecutionDoesNotDoubleApply() throws {
        let env = makeEnv()
        let bench = insertExercise(env, name: "Bench Press")
        let curl = insertExercise(env, name: "Curl")
        let routine = try seedRoutine(env, exercises: [bench])
        let benchSlot = try #require(routine.routineExercisesList.first)

        let newSlot = UUID()
        let retained = completedExercise(
            slotID: benchSlot.id, exerciseId: bench.id,
            sets: [Fixtures.makeSet(id: benchSlot.setsList.first!.id)]
        )
        let added = completedExercise(
            slotID: newSlot, exerciseId: curl.id, name: "Curl", order: 1,
            sets: [Fixtures.makeSet(id: UUID())]
        )
        let incoming = workout(routineId: routine.id, exercises: [retained, added], added: [newSlot])

        // First commit.
        let (service1, _) = env.makeService()
        guard case .applied = service1.execute(incoming) else {
            Issue.record("Expected applied outcome on first execute"); return
        }
        // Re-drain the same transaction (e.g. receipt-write loss): a fresh
        // transaction, same payload. The atomic witness makes it idempotent.
        let (service2, _) = env.makeService()
        guard case .applied = service2.execute(incoming) else {
            Issue.record("Expected idempotent applied outcome on re-run"); return
        }

        let committed = try env.committedRoutine(routine.id)
        #expect(committed.routineExercisesList.filter { $0.id == newSlot }.count == 1)
        #expect(committed.routineExercisesList.count == 2)
    }
}
