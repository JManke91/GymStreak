//
//  WatchSummaryOverloadReceiveTests.swift
//  GymStreakTests
//
//  Ticket 05 (progressive-overload resurface): applying the weight increase
//  from the Watch's POST-WORKOUT RECAP, after the completed workout is frozen
//  and possibly already transferred or ingested. See
//  `WatchSummaryOverloadPolicyTests.swift` for the shared row state machine,
//  `WatchSummaryOverloadWireTests.swift` for the wire correlation and outgoing
//  ordering, and `WatchSummaryOverloadReceiveTests.swift` for the iOS side.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - iOS receive side

@Suite(.serialized)
@MainActor
struct WatchSummaryOverloadCorrelationTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    private func makeStore() throws -> (store: WorkoutIngestReceiptStore, directory: URL) {
        let directory = try Fixtures.makeTempDirectory()
        return (WorkoutIngestReceiptStore(directory: directory), directory)
    }

    @Test
    func anUnknownWorkoutHasNoAppliedOverloads() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await store.appliedOverloads(forWorkout: UUID()).isEmpty)
    }

    @Test
    func recordedCorrelationIsReadBackBySlot() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workoutID = UUID(), slotID = UUID()

        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotID, newWeight: 62.5)

        let applied = await store.appliedOverloads(forWorkout: workoutID)
        #expect(applied == [slotID: AppliedOverloadRecord(newWeight: 62.5)])
        // Scoped to its own workout — another session is unaffected.
        #expect(await store.appliedOverloads(forWorkout: UUID()).isEmpty)
    }

    @Test
    func severalExercisesOfOneWorkoutEachKeepTheirOwnWeight() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workoutID = UUID(), slotA = UUID(), slotB = UUID()

        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotA, newWeight: 62.5)
        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotB, newWeight: 30)

        let applied = await store.appliedOverloads(forWorkout: workoutID)
        #expect(applied == [
            slotA: AppliedOverloadRecord(newWeight: 62.5),
            slotB: AppliedOverloadRecord(newWeight: 30)
        ])
    }

    /// A pyramid or drop scheme has no single new weight. Recording one anyway
    /// would make History claim a number that is wrong for every set but the
    /// first — exactly the claim the Watch recap refuses to make.
    @Test
    func aNonuniformSchemeIsRecordedAsAppliedWithNoWeight() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workoutID = UUID(), slotID = UUID()

        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotID, newWeight: nil)

        let applied = await store.appliedOverloads(forWorkout: workoutID)
        #expect(applied == [slotID: AppliedOverloadRecord(newWeight: nil)])
        // Still present — "applied" and "applied to X" are different facts.
        #expect(applied[slotID] != nil)
    }

    @Test
    func rerecordingTheSameSlotIsIdempotent() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workoutID = UUID(), slotID = UUID()

        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotID, newWeight: 62.5)
        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotID, newWeight: 62.5)

        let applied = await store.appliedOverloads(forWorkout: workoutID)
        #expect(applied == [slotID: AppliedOverloadRecord(newWeight: 62.5)])
    }

    /// Written when the transaction applies, read when the workout is shown —
    /// so it survives a fresh store instance and needs no live process state.
    @Test
    func correlationSurvivesAcrossStoreInstances() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workoutID = UUID(), slotID = UUID()

        store.recordAppliedOverload(workoutID: workoutID, routineExerciseID: slotID, newWeight: 62.5)

        let reopened = WorkoutIngestReceiptStore(directory: directory)
        let applied = await reopened.appliedOverloads(forWorkout: workoutID)
        #expect(applied == [slotID: AppliedOverloadRecord(newWeight: 62.5)])
    }
}

// MARK: - iOS apply: template only, history untouched

@Suite(.serialized)
@MainActor
struct WatchSummaryOverloadApplyTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    /// A routine with one slot at 12 × 60 kg, plus an already-ingested workout
    /// recording that performance against the same slot.
    private func makeEnv() throws -> (
        container: ModelContainer, context: ModelContext,
        routine: Routine, slot: RoutineExercise, workoutID: UUID
    ) {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext

        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let routine = Routine(name: "Push Day")
        let slot = RoutineExercise(exercise: exercise, order: 0)
        slot.routine = routine
        let set = ExerciseSet(reps: 12, weight: 60, restTime: 60, order: 0)
        set.routineExercise = slot
        slot.sets?.append(set)
        routine.routineExercises?.append(slot)
        context.insert(routine)
        try context.save()

        let workoutID = UUID()
        let workout = Fixtures.makeWorkout(
            id: workoutID, routineId: routine.id, shouldUpdateTemplate: false,
            exercises: [Fixtures.makeExercise(
                id: slot.id,
                sets: [Fixtures.makeSet(
                    id: set.id, plannedReps: 12, actualReps: 12,
                    plannedWeight: 60, actualWeight: 60
                )]
            )]
        )
        let tx = SwiftDataWorkoutHistoryTransactionFactory(container: container).makeIsolatedTransaction()
        _ = WatchTemplateTransactionService(
            routineRepository: tx.routineRepository,
            workoutSessionRepository: tx.workoutSessionRepository,
            exerciseRepository: tx.exerciseRepository
        ).execute(workout.toIncomingWatchWorkout())

        return (container, context, routine, slot, workoutID)
    }

    private func makeService(_ container: ModelContainer) -> WatchTemplateTransactionService {
        let tx = SwiftDataWorkoutHistoryTransactionFactory(container: container).makeIsolatedTransaction()
        return WatchTemplateTransactionService(
            routineRepository: tx.routineRepository,
            workoutSessionRepository: tx.workoutSessionRepository,
            exerciseRepository: tx.exerciseRepository
        )
    }

    private func correlatedIntent(
        slot: RoutineExercise, workoutID: UUID
    ) -> IncomingProgressiveOverload {
        var wire = WatchProgressiveOverloadIntent(
            routineExerciseID: slot.id, alternativeID: nil, targetRepMin: 8,
            setChanges: slot.setsList.map {
                WatchTemplateSetChange(
                    setID: $0.id, expectedReps: 12, expectedWeight: 60,
                    proposedReps: 8, proposedWeight: 62.5
                )
            }
        )
        wire.sourceWorkoutID = workoutID
        wire.sourceRoutineExerciseID = slot.id
        return wire.toIncomingProgressiveOverload()
    }

    /// The template moves; the recorded performance does not. This is the
    /// difference from the mid-workout path, which swaps the recorded values
    /// into `planned` before the payload is frozen.
    @Test
    func aRecapOverloadRaisesTheTemplateAndLeavesTheRecordedWorkoutUntouched() throws {
        let (container, _, routine, slot, workoutID) = try makeEnv()

        let sessions = SwiftDataWorkoutSessionRepository(modelContext: ModelContext(container)).fetchAll()
        #expect(sessions.count == 1)

        let outcome = makeService(container).executeProgressiveOverload(
            correlatedIntent(slot: slot, workoutID: workoutID), routineID: routine.id
        )
        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }

        let fresh = ModelContext(container)
        let committedRoutine = try #require(
            SwiftDataRoutineRepository(modelContext: fresh).fetch(id: routine.id)
        )
        let templateSet = try #require(committedRoutine.routineExercisesList[0].setsList.first)
        #expect(templateSet.reps == 8 && templateSet.weight == 62.5)

        // No second history record, and the existing one is byte-for-byte what
        // was performed — including the flag that would redirect every
        // aggregator to the planned values.
        let after = SwiftDataWorkoutSessionRepository(modelContext: fresh).fetchAll()
        #expect(after.count == 1)
        let recorded = try #require(after.first?.workoutExercisesList.first)
        #expect(!recorded.progressiveOverloadApplied)
        let recordedSet = try #require(recorded.setsList.first)
        #expect(recordedSet.actualReps == 12 && recordedSet.actualWeight == 60)
        #expect(recordedSet.plannedReps == 12 && recordedSet.plannedWeight == 60)
    }

    /// The correlation is a hint, not a precondition: applying before the
    /// workout has been ingested must behave identically.
    @Test
    func aRecapOverloadAppliesEvenWhenItsWorkoutWasNeverIngested() throws {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let routine = Routine(name: "Push Day")
        let slot = RoutineExercise(exercise: exercise, order: 0)
        slot.routine = routine
        let set = ExerciseSet(reps: 12, weight: 60, restTime: 60, order: 0)
        set.routineExercise = slot
        slot.sets?.append(set)
        routine.routineExercises?.append(slot)
        context.insert(routine)
        try context.save()

        let outcome = makeService(container).executeProgressiveOverload(
            correlatedIntent(slot: slot, workoutID: UUID()), routineID: routine.id
        )
        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }

        let fresh = ModelContext(container)
        let committed = try #require(SwiftDataRoutineRepository(modelContext: fresh).fetch(id: routine.id))
        #expect(try #require(committed.routineExercisesList[0].setsList.first).weight == 62.5)
        // Still no fabricated history for a workout iOS has never seen.
        #expect(SwiftDataWorkoutSessionRepository(modelContext: fresh).fetchAll().isEmpty)
    }

    /// A conflict rejects the whole transaction, so nothing was applied and
    /// nothing may be recorded as applied either.
    @Test
    func aRejectedRecapOverloadChangesNeitherTemplateNorHistory() throws {
        let (container, context, routine, slot, workoutID) = try makeEnv()
        // The user edited the template on iPhone since the Watch read it.
        try #require(slot.setsList.first).weight = 70
        try context.save()

        let outcome = makeService(container).executeProgressiveOverload(
            correlatedIntent(slot: slot, workoutID: workoutID), routineID: routine.id
        )
        guard case .rejected = outcome else { Issue.record("expected rejected, got \(outcome)"); return }

        let fresh = ModelContext(container)
        let committed = try #require(SwiftDataRoutineRepository(modelContext: fresh).fetch(id: routine.id))
        let templateSet = try #require(committed.routineExercisesList[0].setsList.first)
        #expect(templateSet.weight == 70 && templateSet.reps == 12)
        let recorded = try #require(
            SwiftDataWorkoutSessionRepository(modelContext: fresh).fetchAll()
                .first?.workoutExercisesList.first
        )
        #expect(!recorded.progressiveOverloadApplied)
    }

    /// Redelivery re-applies the same absolute end state rather than
    /// incrementing again — the recap path inherits this from ticket 04.
    @Test
    func redeliveringARecapOverloadDoesNotIncrementTwice() throws {
        let (container, _, routine, slot, workoutID) = try makeEnv()
        let request = correlatedIntent(slot: slot, workoutID: workoutID)

        _ = makeService(container).executeProgressiveOverload(request, routineID: routine.id)
        let outcome = makeService(container).executeProgressiveOverload(request, routineID: routine.id)

        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }
        let fresh = ModelContext(container)
        let committed = try #require(SwiftDataRoutineRepository(modelContext: fresh).fetch(id: routine.id))
        #expect(try #require(committed.routineExercisesList[0].setsList.first).weight == 62.5)
    }
}
