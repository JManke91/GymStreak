//
//  WatchRestTemplateTests.swift
//  GymStreakTests
//
//  Rest duration in the watch template transaction (watch-rest-adjust ticket
//  04): a rest adjusted on the watch reaches the routine when the user finishes
//  with "Save & Update Template", and stays session-only when they decline.
//  Covers four seams:
//    • the wire pair `restTime`/`plannedRestTime` and its backward-compat;
//    • the finish-dialog change detection (`WatchWorkoutInteractionPolicy`,
//      `ActiveWorkoutSet`), reached through the iOS-target copies;
//    • the watch optimistic overlay (`WatchRoutineTemplateFold`);
//    • the iOS authoritative merge (`WatchTemplateTransactionService`).
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - Change detection (watch)

@Suite(.serialized)
@MainActor
struct WatchRestChangeDetectionTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private func activeSet(restTime: TimeInterval, plannedRestTime: TimeInterval?) -> ActiveWorkoutSet {
        ActiveWorkoutSet(
            id: UUID(), plannedReps: 10, actualReps: 10, plannedWeight: 60, actualWeight: 60,
            restTime: restTime, plannedRestTime: plannedRestTime, completedAt: nil, order: 0
        )
    }

    @Test
    func adjustedRestIsModifiedButNeverCountsAsAModifiedSet() {
        let adjusted = activeSet(restTime: 90, plannedRestTime: 60)
        #expect(adjusted.wasRestAdjusted)
        // A rest change is one change per exercise; counting it per set would
        // inflate the "you modified N sets" message.
        #expect(!adjusted.wasModified)

        // Untouched, and — same thing by value — reverted to the baseline by
        // the "this rest only" scope.
        #expect(!activeSet(restTime: 60, plannedRestTime: 60).wasRestAdjusted)
        // An adjustment kept from an earlier rest still reads as intent, even
        // after a later one is reverted to it.
        #expect(activeSet(restTime: 90, plannedRestTime: 60).wasRestAdjusted)
        // No baseline recorded (checkpoint from a build before the field) is
        // never rest intent.
        #expect(!activeSet(restTime: 90, plannedRestTime: nil).wasRestAdjusted)
    }

    @Test
    func restOnlyChangeOffersTheTemplateUpdateWithItsOwnMessage() {
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0, hasStructuralChanges: false, hasRestChanges: true
        ) == .restOnly)
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0, hasStructuralChanges: false, hasRestChanges: false
        ) == .unchanged)
        // Rest is the weakest signal: a set or structural change already offers
        // the update and the rest rides along with it.
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 2, hasStructuralChanges: false, hasRestChanges: true
        ) == .setsOnly(count: 2))
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0, hasStructuralChanges: true, hasRestChanges: true
        ) == .structuralOnly)
    }

    @Test
    func thePayloadNamesExactlyTheSlotsWhoseRestChanged() {
        let adjusted = UUID(), untouched = UUID(), noBaseline = UUID()
        let workout = Fixtures.makeWorkout(shouldUpdateTemplate: true, exercises: [
            Fixtures.makeExercise(id: adjusted, sets: [
                Fixtures.makeSet(order: 0, restTime: 90, plannedRestTime: 60),
                Fixtures.makeSet(order: 1, restTime: 90, plannedRestTime: 60)
            ]),
            Fixtures.makeExercise(id: untouched, sets: [
                Fixtures.makeSet(restTime: 60, plannedRestTime: 60)
            ]),
            Fixtures.makeExercise(id: noBaseline, sets: [
                Fixtures.makeSet(restTime: 90, plannedRestTime: nil)
            ])
        ])
        // Drives the finalization diagnostic and the optimistic fold's intent
        // test, so it must name each slot once and only the changed ones.
        #expect(workout.restAdjustedExerciseIDs == [adjusted])
    }

    @Test
    func restBaselineRoundTripsThroughTheWireAndTheMapper() throws {
        let set = Fixtures.makeSet(restTime: 90, plannedRestTime: 60)
        let workout = Fixtures.makeWorkout(
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(sets: [set])]
        )
        let decoded = try JSONDecoder().decode(
            CompletedWatchWorkout.self, from: JSONEncoder().encode(workout)
        )
        #expect(decoded.exercises[0].sets[0].plannedRestTime == 60)
        #expect(decoded.exercises[0].sets[0].restTime == 90)

        let incoming = decoded.toIncomingWatchWorkout()
        #expect(incoming.exercises[0].sets[0].plannedRestTime == 60)
        #expect(incoming.exercises[0].sets[0].restTime == 90)
    }

    @Test
    func payloadFromAWatchBuildWithoutTheBaselineDecodesAsNoRestIntent() throws {
        // A pre-rest-adjustment watch build simply omits the key.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "routineId": "\(UUID().uuidString)",
          "routineName": "Push Day",
          "startTime": 700000000,
          "endTime": 700003600,
          "shouldUpdateTemplate": true,
          "exercises": [{
            "id": "\(UUID().uuidString)",
            "name": "Bench Press",
            "muscleGroup": "Chest",
            "order": 0,
            "supersetOrder": 0,
            "sets": [{
              "id": "\(UUID().uuidString)",
              "plannedReps": 10, "actualReps": 10,
              "plannedWeight": 60, "actualWeight": 60,
              "restTime": 60, "isCompleted": true, "order": 0
            }]
          }]
        }
        """
        let decoded = try JSONDecoder().decode(CompletedWatchWorkout.self, from: Data(json.utf8))
        #expect(decoded.exercises[0].sets[0].plannedRestTime == nil)
        #expect(decoded.toIncomingWatchWorkout().exercises[0].sets[0].plannedRestTime == nil)
    }
}

// MARK: - Watch optimistic overlay

@Suite(.serialized)
@MainActor
struct WatchRestFoldTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private func routine(id: UUID, slotID: UUID, setIDs: [UUID], restTime: TimeInterval = 60) -> WatchRoutine {
        WatchRoutine(id: id, name: "Push", exercises: [WatchExercise(
            id: slotID,
            name: "Bench Press",
            muscleGroup: "Chest",
            sets: setIDs.enumerated().map { index, setID in
                WatchSet(id: setID, reps: 10, weight: 60 + Double(index), restTime: restTime)
            },
            order: 0,
            supersetId: nil,
            supersetOrder: 0
        )])
    }

    private func workout(
        routineId: UUID, exercises: [CompletedWatchExercise],
        shouldUpdateTemplate: Bool = true, overloadApplied: [UUID] = []
    ) -> CompletedWatchWorkout {
        var w = Fixtures.makeWorkout(
            routineId: routineId, shouldUpdateTemplate: shouldUpdateTemplate, exercises: exercises
        )
        w.overloadAppliedExerciseIDs = overloadApplied
        return w
    }

    @Test
    func adjustedRestFoldsOntoEverySetOfTheExercise() {
        let routineID = UUID(), slotID = UUID()
        let setIDs = [UUID(), UUID(), UUID()]
        let base = routine(id: routineID, slotID: slotID, setIDs: setIDs)
        // Only the first two sets were performed; the whole scheme still takes
        // the new rest, because rest is one value per exercise.
        let completed = Fixtures.makeExercise(id: slotID, sets: [
            Fixtures.makeSet(id: setIDs[0], order: 0, restTime: 90, plannedRestTime: 60),
            Fixtures.makeSet(id: setIDs[1], order: 1, restTime: 90, plannedRestTime: 60)
        ])

        let folded = WatchRoutineTemplateFold.apply(
            workout(routineId: routineID, exercises: [completed]), to: base
        )
        #expect(folded.exercises[0].sets.map(\.restTime) == [90, 90, 90])
        #expect(folded.exercises[0].sets.map(\.reps) == [10, 10, 10])
    }

    @Test
    func unchangedRestLeavesTheOverlayExactlyAsItWas() {
        let routineID = UUID(), slotID = UUID(), setID = UUID()
        let base = routine(id: routineID, slotID: slotID, setIDs: [setID])
        let completed = Fixtures.makeExercise(id: slotID, sets: [
            Fixtures.makeSet(id: setID, actualReps: 12, restTime: 60, plannedRestTime: 60)
        ])

        let folded = WatchRoutineTemplateFold.apply(
            workout(routineId: routineID, exercises: [completed]), to: base
        )
        #expect(folded.exercises[0].sets[0].restTime == 60)
        #expect(folded.exercises[0].sets[0].reps == 12)
    }

    @Test
    func decliningTheTemplateUpdateFoldsNothing() {
        let routineID = UUID(), slotID = UUID(), setID = UUID()
        let base = routine(id: routineID, slotID: slotID, setIDs: [setID])
        let completed = Fixtures.makeExercise(id: slotID, sets: [
            Fixtures.makeSet(id: setID, restTime: 90, plannedRestTime: 60)
        ])

        let folded = WatchRoutineTemplateFold.apply(
            workout(routineId: routineID, exercises: [completed], shouldUpdateTemplate: false),
            to: base
        )
        #expect(folded.exercises[0].sets[0].restTime == 60)
    }

    @Test
    func overloadResolvedExerciseTakesTheRestButKeepsItsValues() {
        let routineID = UUID(), slotID = UUID(), setID = UUID()
        let base = routine(id: routineID, slotID: slotID, setIDs: [setID])
        let completed = Fixtures.makeExercise(id: slotID, sets: [
            Fixtures.makeSet(id: setID, plannedReps: 10, actualReps: 12, restTime: 90, plannedRestTime: 60)
        ])

        let folded = WatchRoutineTemplateFold.apply(
            workout(routineId: routineID, exercises: [completed], overloadApplied: [slotID]),
            to: base
        )
        #expect(folded.exercises[0].sets[0].restTime == 90)
        // The overload transaction owns reps/weight; this fold must not regress
        // them with the pre-increase performance.
        #expect(folded.exercises[0].sets[0].reps == 10)
    }
}

// MARK: - iOS authoritative merge

@Suite(.serialized)
@MainActor
struct WatchRestMergeTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext

        func makeService() -> WatchTemplateTransactionService {
            let tx = SwiftDataWorkoutHistoryTransactionFactory(container: container).makeIsolatedTransaction()
            return WatchTemplateTransactionService(
                routineRepository: tx.routineRepository,
                workoutSessionRepository: tx.workoutSessionRepository,
                exerciseRepository: tx.exerciseRepository
            )
        }

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

    /// Seeds a routine whose slots each carry `setCount` sets at 60 s rest.
    @discardableResult
    private func seedRoutine(
        _ env: Env, slotCount: Int = 1, setCount: Int = 3, supersetId: UUID? = nil
    ) throws -> Routine {
        let routine = Routine(name: "Push Day")
        for order in 0..<slotCount {
            let exercise = Exercise(name: "Exercise \(order)")
            env.context.insert(exercise)
            let slot = RoutineExercise(exercise: exercise, order: order)
            slot.supersetId = supersetId
            slot.supersetOrder = order
            slot.routine = routine
            for setOrder in 0..<setCount {
                let set = ExerciseSet(reps: 10, weight: 60, restTime: 60, order: setOrder)
                set.routineExercise = slot
                slot.sets?.append(set)
            }
            routine.routineExercises?.append(slot)
        }
        env.context.insert(routine)
        try env.context.save()
        return routine
    }

    /// A payload mirroring one routine slot, resting for `restTime` where the
    /// workout started at `plannedRestTime`.
    private func completed(
        _ slot: RoutineExercise,
        restTime: TimeInterval,
        plannedRestTime: TimeInterval? = 60,
        actualReps: Int? = nil
    ) -> CompletedWatchExercise {
        CompletedWatchExercise(
            id: slot.id,
            name: slot.exercise?.name ?? "Ex",
            muscleGroup: "Chest",
            sets: slot.setsList.enumerated().map { index, set in
                Fixtures.makeSet(
                    id: set.id,
                    actualReps: actualReps ?? set.reps,
                    order: index,
                    restTime: restTime,
                    plannedRestTime: plannedRestTime
                )
            },
            order: slot.order,
            supersetId: slot.supersetId,
            supersetOrder: slot.supersetOrder,
            exerciseId: slot.exercise?.id
        )
    }

    private func workout(
        routineId: UUID,
        exercises: [CompletedWatchExercise],
        added: [UUID] = [],
        overloadApplied: [UUID] = [],
        transactionID: UUID = UUID(),
        workoutID: UUID = UUID()
    ) -> IncomingWatchWorkout {
        var w = Fixtures.makeWorkout(
            id: workoutID,
            routineId: routineId, shouldUpdateTemplate: true, exercises: exercises,
            transactionID: transactionID, senderEpoch: UUID(), sequence: 0
        )
        w.addedRoutineExerciseIDs = added
        w.overloadAppliedExerciseIDs = overloadApplied
        return w.toIncomingWatchWorkout()
    }

    @Test
    func restOnlyChangeReachesEveryTemplateSetOfTheExercise() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env)
        let slot = try #require(routine.routineExercisesList.first)

        let outcome = env.makeService().execute(
            workout(routineId: routine.id, exercises: [completed(slot, restTime: 90)])
        )

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let merged = try env.committedRoutine(routine.id)
        let mergedSets = try #require(merged.routineExercisesList.first).setsList
        #expect(mergedSets.map(\.restTime) == [90, 90, 90])
        // Values were never modified, so the merge must not have touched them.
        #expect(mergedSets.allSatisfy { $0.reps == 10 && $0.weight == 60 })
        #expect(env.committedSessions().first?.didUpdateTemplate == true)
    }

    @Test
    func restAndValueChangesOnTheSameSetBothCommit() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env, setCount: 2)
        let slot = try #require(routine.routineExercisesList.first)

        let outcome = env.makeService().execute(workout(
            routineId: routine.id,
            exercises: [completed(slot, restTime: 120, actualReps: 12)]
        ))

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let mergedSets = try #require(env.committedRoutine(routine.id).routineExercisesList.first).setsList
        #expect(mergedSets.map(\.restTime) == [120, 120])
        #expect(mergedSets.map(\.reps) == [12, 12])
    }

    @Test
    func supersetGroupMembersEachTakeTheAdjustedRest() throws {
        let env = makeEnv()
        let group = UUID()
        let routine = try seedRoutine(env, slotCount: 2, setCount: 2, supersetId: group)
        let slots = routine.routineExercisesList

        // Ticket 01 writes a round's rest to every member of the group, so the
        // payload carries the new value on both slots.
        let outcome = env.makeService().execute(workout(
            routineId: routine.id,
            exercises: slots.map { completed($0, restTime: 45) }
        ))

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let merged = try env.committedRoutine(routine.id)
        #expect(merged.routineExercisesList.allSatisfy { slot in
            slot.setsList.allSatisfy { $0.restTime == 45 }
        })
    }

    @Test
    func overloadResolvedSlotTakesTheRestButKeepsItsCommittedValues() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env, setCount: 2)
        let slot = try #require(routine.routineExercisesList.first)

        let outcome = env.makeService().execute(workout(
            routineId: routine.id,
            exercises: [completed(slot, restTime: 90, actualReps: 12)],
            overloadApplied: [slot.id]
        ))

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let mergedSets = try #require(env.committedRoutine(routine.id).routineExercisesList.first).setsList
        #expect(mergedSets.allSatisfy { $0.restTime == 90 })
        // The progressive-overload transaction owns reps/weight for this slot.
        #expect(mergedSets.allSatisfy { $0.reps == 10 })
    }

    @Test
    func payloadWithoutARestBaselineLeavesTheTemplateRestAlone() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env, setCount: 2)
        let slot = try #require(routine.routineExercisesList.first)

        // An old watch build (no baseline) whose rest happens to differ from a
        // rest the user has since changed on the iPhone: no intent, no write.
        let outcome = env.makeService().execute(workout(
            routineId: routine.id,
            exercises: [completed(slot, restTime: 30, plannedRestTime: nil, actualReps: 12)]
        ))

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let mergedSets = try #require(env.committedRoutine(routine.id).routineExercisesList.first).setsList
        #expect(mergedSets.allSatisfy { $0.restTime == 60 })
        #expect(mergedSets.allSatisfy { $0.reps == 12 })
    }

    @Test
    func rejectedTransactionSavesHistoryWithoutApplyingTheRest() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env)
        let slot = try #require(routine.routineExercisesList.first)

        // An added slot whose exercise cannot be resolved rejects the WHOLE
        // request — including the rest change on the retained slot.
        let orphan = UUID()
        let added = CompletedWatchExercise(
            id: orphan, name: "Ghost", muscleGroup: "Chest",
            sets: [Fixtures.makeSet()], order: 1, supersetId: nil, supersetOrder: 0,
            exerciseId: UUID()
        )
        let outcome = env.makeService().execute(workout(
            routineId: routine.id,
            exercises: [completed(slot, restTime: 90), added],
            added: [orphan]
        ))

        guard case .rejected = outcome else {
            Issue.record("expected rejected, got \(outcome)")
            return
        }
        let mergedSets = try #require(env.committedRoutine(routine.id).routineExercisesList.first).setsList
        #expect(mergedSets.allSatisfy { $0.restTime == 60 })
        #expect(env.committedSessions().count == 1)
        #expect(env.committedSessions().first?.didUpdateTemplate == false)
    }

    /// The arrival shape production actually uses (ADR 0001): history travels as
    /// its own ungated entry and usually commits FIRST, so the template half
    /// meets an already-saved session and takes `stageHistory`'s `.duplicate`
    /// branch. Every other test here stages history and template together.
    @Test
    func restAppliesWhenTheHistoryHalfAlreadyCommitted() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env, setCount: 3)
        let slot = try #require(routine.routineExercisesList.first)
        let exercises = [completed(slot, restTime: 185, plannedRestTime: 120)]

        // 1. The history half: no template intent, no transaction identity.
        var historyHalf = Fixtures.makeWorkout(
            routineId: routine.id, shouldUpdateTemplate: false, exercises: exercises
        )
        historyHalf.templateTransactionID = nil
        let historyTx = SwiftDataWorkoutHistoryTransactionFactory(container: env.container)
            .makeIsolatedTransaction()
        _ = WatchWorkoutIngestionService(
            routineRepository: historyTx.routineRepository,
            workoutSessionRepository: historyTx.workoutSessionRepository
        ).ingest(historyHalf.toIncomingWatchWorkout())

        // 2. The template half, same workout id, arriving second.
        let outcome = env.makeService().execute(workout(
            routineId: routine.id, exercises: exercises, workoutID: historyHalf.id
        ))

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let mergedSets = try #require(env.committedRoutine(routine.id).routineExercisesList.first).setsList
        #expect(mergedSets.allSatisfy { $0.restTime == 185 })
        #expect(env.committedSessions().count == 1)
    }

    @Test
    func reapplyingTheSameTransactionIsANoOp() throws {
        let env = makeEnv()
        let routine = try seedRoutine(env, setCount: 2)
        let slot = try #require(routine.routineExercisesList.first)
        let transactionID = UUID()
        let payload = workout(
            routineId: routine.id,
            exercises: [completed(slot, restTime: 90)],
            transactionID: transactionID
        )

        _ = env.makeService().execute(payload)
        // The user then dials the routine's rest somewhere else on the iPhone;
        // a redelivery of the same transaction must not replay over it.
        let edited = try #require(SwiftDataRoutineRepository(modelContext: env.context).fetch(id: routine.id))
        for set in try #require(edited.routineExercisesList.first).setsList {
            set.restTime = 75
        }
        try env.context.save()

        let outcome = env.makeService().execute(payload)

        guard case .applied = outcome else {
            Issue.record("expected applied, got \(outcome)")
            return
        }
        let mergedSets = try #require(env.committedRoutine(routine.id).routineExercisesList.first).setsList
        #expect(mergedSets.allSatisfy { $0.restTime == 75 })
        #expect(env.committedSessions().count == 1)
    }
}
