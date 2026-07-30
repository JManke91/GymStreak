//
//  WatchProgressiveOverloadTests.swift
//  GymStreakTests
//
//  Ticket 04 (progressive-overload resurface): the watch's mid-workout weight
//  increase as a template-ONLY kind of the shared template-transaction
//  protocol. Covers four seams:
//    • the wire contract and its backward decoding;
//    • the watch optimistic fold (`WatchRoutineTemplateFold`), reached through
//      the iOS-target copy — there is no watch unit-test target;
//    • the durable sync-state owner's generic enqueue, sequencing, and FIFO;
//    • the iOS authoritative merge over an isolated one-save transaction, and
//      its interaction with a later completed-workout template transaction.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// MARK: - Wire contract

@Suite(.serialized)
@MainActor
struct WatchProgressiveOverloadWireTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func legacyPayloadWithoutOverloadKeyDecodesAsNoOverload() throws {
        // A pre-ticket-04 watch payload simply lacks the key.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "routineId": "\(UUID().uuidString)",
          "routineName": "Push Day",
          "startTime": 0,
          "endTime": 600,
          "exercises": [],
          "shouldUpdateTemplate": true
        }
        """
        let decoded = try JSONDecoder().decode(CompletedWatchWorkout.self, from: Data(json.utf8))
        #expect(decoded.overloadAppliedExerciseIDs == nil)
        #expect(decoded.toIncomingWatchWorkout().overloadAppliedExerciseIDs.isEmpty)
    }

    @Test
    func overloadAppliedIDsRoundTripThroughMapper() throws {
        let slotID = UUID()
        var workout = Fixtures.makeWorkout(
            shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(id: slotID, sets: [Fixtures.makeSet()])]
        )
        workout.overloadAppliedExerciseIDs = [slotID]

        let reencoded = try JSONDecoder().decode(
            CompletedWatchWorkout.self, from: JSONEncoder().encode(workout)
        )
        #expect(reencoded.overloadAppliedExerciseIDs == [slotID])
        #expect(reencoded.toIncomingWatchWorkout().overloadAppliedExerciseIDs == [slotID])
    }

    @Test
    func alternativeRepRangesRoundTripAndDefaultToNilOnOlderSnapshots() throws {
        let alternative = WatchExerciseAlternative(
            id: UUID(), exerciseId: UUID(), name: "Incline Press", muscleGroup: "Chest",
            sets: [], order: 0, loadBehaviorRaw: "resistance", targetRepMin: 6, targetRepMax: 10
        )
        let reencoded = try JSONDecoder().decode(
            WatchExerciseAlternative.self, from: JSONEncoder().encode(alternative)
        )
        #expect(reencoded.targetRepMin == 6)
        #expect(reencoded.targetRepMax == 10)

        // A snapshot cached before the fields existed stays decodable.
        let legacy = """
        {"id":"\(UUID().uuidString)","exerciseId":"\(UUID().uuidString)",
         "name":"Incline Press","muscleGroup":"Chest","sets":[],"order":0}
        """
        let old = try JSONDecoder().decode(WatchExerciseAlternative.self, from: Data(legacy.utf8))
        #expect(old.targetRepMin == nil)
        #expect(old.targetRepMax == nil)
    }

    @Test
    func progressiveEnvelopeRoundTripsAndCarriesNoWorkoutCorrelation() throws {
        let envelope = TemplateTransactionEnvelope(
            transactionID: UUID(), senderEpoch: UUID(), routineID: UUID(), sequence: 3,
            workoutID: nil,
            payload: .progressiveOverload(makeIntent())
        )
        let decoded = try JSONDecoder().decode(
            TemplateTransactionEnvelope.self, from: JSONEncoder().encode(envelope)
        )
        #expect(decoded.completedWorkout == nil)
        #expect(decoded.payload.progressiveOverload != nil)
        #expect(decoded.isInternallyConsistent)
    }

    @Test
    func progressiveEnvelopeWithWorkoutCorrelationIsInconsistent() {
        // A non-nil workoutID here would collide with the workout-id matching
        // in the sync-state owner and could swallow a real completed workout.
        let envelope = TemplateTransactionEnvelope(
            transactionID: UUID(), senderEpoch: UUID(), routineID: UUID(), sequence: 0,
            workoutID: UUID(),
            payload: .progressiveOverload(makeIntent())
        )
        #expect(!envelope.isInternallyConsistent)
    }

    @Test(arguments: [
        "emptySetChanges", "duplicateSetIDs", "negativeWeight", "nonFiniteWeight",
        "repsNotResetToMinimum", "invalidRepMinimum", "unsupportedSchema"
    ])
    func malformedIntentsFailValidation(_ variant: String) {
        let setID = UUID()
        var intent = makeIntent(setID: setID)
        switch variant {
        case "emptySetChanges":
            intent = WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8, setChanges: []
            )
        case "duplicateSetIDs":
            intent = WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID), makeChange(setID: setID)]
            )
        case "negativeWeight":
            intent = WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID, proposedWeight: -1)]
            )
        case "nonFiniteWeight":
            intent = WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID, proposedWeight: .infinity)]
            )
        case "repsNotResetToMinimum":
            intent = WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID, proposedReps: 11)]
            )
        case "invalidRepMinimum":
            intent = WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 0,
                setChanges: [makeChange(setID: setID, proposedReps: 0)]
            )
        case "unsupportedSchema":
            intent.schemaVersion = WatchProgressiveOverloadIntent.currentSchemaVersion + 1
        default:
            Issue.record("unhandled variant \(variant)")
        }
        #expect(!intent.isWellFormed, "\(variant) must not validate")
    }

    @Test
    func wellFormedIntentValidates() {
        #expect(makeIntent().isWellFormed)
    }

    /// The same invariant deliberately lives twice inside the iOS module: on the
    /// WIRE type (which `WatchRoutineTemplateFold` uses for the watch's
    /// optimistic overlay) and on the DOMAIN type (which the authoritative apply
    /// uses). Drift between them would let the overlay show something iOS never
    /// commits — exactly what the three-way comparison exists to prevent — so
    /// this pins them together.
    @Test
    func wireAndDomainValidationAgreeOnEveryCase() {
        let setID = UUID(), otherID = UUID()
        let cases: [(name: String, intent: WatchProgressiveOverloadIntent)] = [
            ("well-formed", makeIntent(setID: setID)),
            ("empty setChanges", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8, setChanges: []
            )),
            ("duplicate setID", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID), makeChange(setID: setID)]
            )),
            ("two distinct setIDs", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID), makeChange(setID: otherID)]
            )),
            ("proposedReps != targetRepMin", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID, proposedReps: 11)]
            )),
            ("non-finite weight", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID, proposedWeight: .nan)]
            )),
            ("negative weight", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
                setChanges: [makeChange(setID: setID, expectedWeight: -0.5)]
            )),
            ("invalid rep minimum", WatchProgressiveOverloadIntent(
                routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 0,
                setChanges: [makeChange(setID: setID, proposedReps: 0)]
            ))
        ]
        for (name, wire) in cases {
            #expect(
                wire.isWellFormed == wire.toIncomingProgressiveOverload().isWellFormed,
                "wire and domain validation disagree for: \(name)"
            )
        }

        // The float tolerance must match on both sides of the boundary too,
        // including a pair that straddles it.
        let pairs: [(Double, Double)] = [(60, 60), (60, 60.00005), (60, 60.001), (60, 62.5), (0, 0)]
        for (lhs, rhs) in pairs {
            #expect(
                WatchTemplateSetChange.weightsMatch(lhs, rhs)
                    == IncomingTemplateSetChange.weightsMatch(lhs, rhs),
                "wire and domain weight tolerance disagree for \(lhs) vs \(rhs)"
            )
        }
    }

    // MARK: Helpers

    private func makeChange(
        setID: UUID = UUID(),
        expectedReps: Int = 12, expectedWeight: Double = 60,
        proposedReps: Int = 8, proposedWeight: Double = 62.5
    ) -> WatchTemplateSetChange {
        WatchTemplateSetChange(
            setID: setID, expectedReps: expectedReps, expectedWeight: expectedWeight,
            proposedReps: proposedReps, proposedWeight: proposedWeight
        )
    }

    private func makeIntent(setID: UUID = UUID()) -> WatchProgressiveOverloadIntent {
        WatchProgressiveOverloadIntent(
            routineExerciseID: UUID(), alternativeID: nil, targetRepMin: 8,
            setChanges: [makeChange(setID: setID)]
        )
    }
}

// MARK: - Watch optimistic fold

@Suite(.serialized)
@MainActor
struct WatchProgressiveOverloadFoldTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func foldAppliesProposedValuesToThePrimaryScheme() {
        let slotID = UUID(), setID = UUID()
        let routine = Fixtures.makeWatchRoutine(
            exerciseId: slotID, setId: setID, reps: 12, weight: 60
        )
        let folded = WatchRoutineTemplateFold.apply(
            intent(slotID: slotID, setID: setID), to: routine
        )
        let set = folded.exercises[0].sets[0]
        #expect(set.reps == 8)
        #expect(set.weight == 62.5)
    }

    @Test
    func foldIsIdempotentUnderDuplicateDelivery() {
        let slotID = UUID(), setID = UUID()
        let routine = Fixtures.makeWatchRoutine(exerciseId: slotID, setId: setID, reps: 12, weight: 60)
        let once = WatchRoutineTemplateFold.apply(intent(slotID: slotID, setID: setID), to: routine)
        let twice = WatchRoutineTemplateFold.apply(intent(slotID: slotID, setID: setID), to: once)
        #expect(once == twice)
        #expect(twice.exercises[0].sets[0].weight == 62.5)
    }

    @Test
    func foldLeavesAThirdValueAlone() {
        // The authoritative base moved to a value the watch never saw; iOS
        // resolves that conflict, so the overlay must not guess.
        let slotID = UUID(), setID = UUID()
        let routine = Fixtures.makeWatchRoutine(exerciseId: slotID, setId: setID, reps: 12, weight: 75)
        let folded = WatchRoutineTemplateFold.apply(intent(slotID: slotID, setID: setID), to: routine)
        #expect(folded.exercises[0].sets[0].weight == 75)
        #expect(folded.exercises[0].sets[0].reps == 12)
    }

    @Test
    func foldWritesIntoTheAlternativeSchemeAndLeavesThePrimaryUntouched() {
        let slotID = UUID(), primarySetID = UUID()
        let alternativeID = UUID(), alternativeSetID = UUID()
        var routine = Fixtures.makeWatchRoutine(
            exerciseId: slotID, setId: primarySetID, reps: 12, weight: 60
        )
        let primary = routine.exercises[0]
        routine = WatchRoutine(id: routine.id, name: routine.name, exercises: [
            WatchExercise(
                id: primary.id, name: primary.name, muscleGroup: primary.muscleGroup,
                sets: primary.sets, order: 0, supersetId: nil, supersetOrder: 0,
                targetRepMin: 8, targetRepMax: 12,
                alternatives: [WatchExerciseAlternative(
                    id: alternativeID, exerciseId: UUID(), name: "Incline Press",
                    muscleGroup: "Chest",
                    sets: [WatchSet(id: alternativeSetID, reps: 12, weight: 40, restTime: 60)],
                    order: 0, loadBehaviorRaw: "resistance", targetRepMin: 8, targetRepMax: 12
                )]
            )
        ])

        let folded = WatchRoutineTemplateFold.apply(
            WatchProgressiveOverloadIntent(
                routineExerciseID: slotID, alternativeID: alternativeID, targetRepMin: 8,
                setChanges: [WatchTemplateSetChange(
                    setID: alternativeSetID, expectedReps: 12, expectedWeight: 40,
                    proposedReps: 8, proposedWeight: 42.5
                )]
            ),
            to: routine
        )

        let alternative = try! #require(folded.exercises[0].alternatives?.first)
        #expect(alternative.sets[0].weight == 42.5)
        #expect(alternative.sets[0].reps == 8)
        // The primary scheme and the alternative's own rep range survive.
        #expect(folded.exercises[0].sets[0].weight == 60)
        #expect(alternative.targetRepMin == 8)
        #expect(alternative.targetRepMax == 12)
    }

    @Test
    func completedWorkoutFoldSkipsOverloadResolvedExercises() {
        // The completed workout replays the performance; those template values
        // belong to the overload transaction, not to this one.
        let slotID = UUID(), setID = UUID()
        let routine = Fixtures.makeWatchRoutine(exerciseId: slotID, setId: setID, reps: 8, weight: 62.5)
        var workout = Fixtures.makeWorkout(
            routineId: routine.id, shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(
                id: slotID,
                sets: [Fixtures.makeSet(
                    id: setID, plannedReps: 12, actualReps: 8, plannedWeight: 60, actualWeight: 62.5
                )]
            )]
        )
        workout.overloadAppliedExerciseIDs = [slotID]

        let folded = WatchRoutineTemplateFold.apply(workout, to: routine)
        #expect(folded.exercises[0].sets[0].reps == 8)
        #expect(folded.exercises[0].sets[0].weight == 62.5)
        #expect(folded == routine, "an overload-resolved slot must be byte-identical")
    }

    private func intent(slotID: UUID, setID: UUID) -> WatchProgressiveOverloadIntent {
        WatchProgressiveOverloadIntent(
            routineExerciseID: slotID, alternativeID: nil, targetRepMin: 8,
            setChanges: [WatchTemplateSetChange(
                setID: setID, expectedReps: 12, expectedWeight: 60,
                proposedReps: 8, proposedWeight: 62.5
            )]
        )
    }
}

// MARK: - Durable sync-state owner

@Suite(.serialized)
@MainActor
struct WatchProgressiveOverloadQueueTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @Test
    func enqueueAllocatesSequenceAndIsImmediatelyTransportEligible() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), transactionID = UUID()

        let entry = try store.enqueue(
            progressiveOverload: intent(slotID: UUID(), setID: UUID()),
            routineID: routineID, transactionID: transactionID
        )

        // No HealthKit finalization to wait for.
        #expect(entry.phase == .transportEligible)
        #expect(entry.workoutID == nil)
        #expect(entry.templateTransaction?.sequence == 0)
        #expect(store.transportEligibleEntries().map(\.id) == [transactionID])
    }

    @Test
    func repeatedEnqueueWithSameTransactionIDDoesNotAllocateASecondSequence() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), transactionID = UUID()
        let overload = intent(slotID: UUID(), setID: UUID())

        let first = try store.enqueue(
            progressiveOverload: overload, routineID: routineID, transactionID: transactionID
        )
        let second = try store.enqueue(
            progressiveOverload: overload, routineID: routineID, transactionID: transactionID
        )

        #expect(first.id == second.id)
        #expect(store.all.count == 1)
        #expect(second.templateTransaction?.sequence == 0)
    }

    @Test
    func failedAtomicWriteEnqueuesNothingAndConsumesNoCounter() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID()

        let restore = try Fixtures.makeReadOnly(directory)
        #expect(throws: (any Error).self) {
            try store.enqueue(
                progressiveOverload: intent(slotID: UUID(), setID: UUID()),
                routineID: routineID, transactionID: UUID()
            )
        }
        restore()

        #expect(store.all.isEmpty)
        // The counter was rolled back, so the next successful enqueue is still 0.
        let entry = try store.enqueue(
            progressiveOverload: intent(slotID: UUID(), setID: UUID()),
            routineID: routineID, transactionID: UUID()
        )
        #expect(entry.templateTransaction?.sequence == 0)
    }

    @Test
    func overloadIsFIFOHeadAndBlocksALaterCompletedWorkoutTransaction() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), overloadID = UUID()

        try store.enqueue(
            progressiveOverload: intent(slotID: UUID(), setID: UUID()),
            routineID: routineID, transactionID: overloadID
        )
        let workout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: true)
        try store.enqueue(workout, phase: .transportEligible)

        // Both are durable, but only the oldest may transport.
        #expect(store.all.count == 2)
        #expect(store.transportEligibleEntries().map(\.id) == [overloadID])
        // The completed workout took the next sequence — it can never overtake.
        let workoutEntry = try #require(store.entry(id: workout.id))
        #expect(workoutEntry.templateTransaction?.sequence == 1)
    }

    @Test
    func declinedTemplateWorkoutStillTransportsWhileAnOverloadIsPending() throws {
        // History must not be held hostage: a no-template workout carries no
        // template intent and is therefore never FIFO-gated.
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)
        let routineID = UUID(), overloadID = UUID()

        try store.enqueue(
            progressiveOverload: intent(slotID: UUID(), setID: UUID()),
            routineID: routineID, transactionID: overloadID
        )
        let workout = Fixtures.makeWorkout(routineId: routineID, shouldUpdateTemplate: false)
        try store.enqueue(workout, phase: .transportEligible)

        let eligible = Set(store.transportEligibleEntries().map(\.id))
        #expect(eligible == [overloadID, workout.id])
    }

    @Test
    func pendingOverloadShowsAsOptimisticOverlayInEffectiveRoutines() throws {
        let directory = try Fixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchSyncStateStore(directory: directory)

        let slotID = UUID(), setID = UUID()
        let routine = Fixtures.makeWatchRoutine(exerciseId: slotID, setId: setID, reps: 12, weight: 60)
        store.applyRoutineContext([routine], header: nil)

        try store.enqueue(
            progressiveOverload: intent(slotID: slotID, setID: setID),
            routineID: routine.id, transactionID: UUID(), routineAnchor: routine
        )

        let effective = try #require(store.effectiveRoutines().first)
        #expect(effective.exercises[0].sets[0].weight == 62.5)
        #expect(effective.exercises[0].sets[0].reps == 8)
    }

    private func intent(slotID: UUID, setID: UUID) -> WatchProgressiveOverloadIntent {
        WatchProgressiveOverloadIntent(
            routineExerciseID: slotID, alternativeID: nil, targetRepMin: 8,
            setChanges: [WatchTemplateSetChange(
                setID: setID, expectedReps: 12, expectedWeight: 60,
                proposedReps: 8, proposedWeight: 62.5
            )]
        )
    }
}

// MARK: - iOS authoritative merge

@Suite(.serialized)
@MainActor
struct WatchProgressiveOverloadMergeTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext

        func makeService() -> (service: WatchTemplateTransactionService, tx: WorkoutHistoryTransaction) {
            let tx = SwiftDataWorkoutHistoryTransactionFactory(container: container).makeIsolatedTransaction()
            return (
                WatchTemplateTransactionService(
                    routineRepository: tx.routineRepository,
                    workoutSessionRepository: tx.workoutSessionRepository,
                    exerciseRepository: tx.exerciseRepository
                ),
                tx
            )
        }

        func committedRoutine(_ id: UUID) throws -> Routine {
            let fresh = ModelContext(container)
            return try #require(SwiftDataRoutineRepository(modelContext: fresh).fetch(id: id))
        }

        func committedSessions() -> [WorkoutSession] {
            SwiftDataWorkoutSessionRepository(modelContext: ModelContext(container)).fetchAll()
        }
    }

    /// A routine with one slot carrying two sets at 12 × 60 kg.
    private func makeEnv() throws -> (env: Env, routine: Routine, slot: RoutineExercise) {
        let container = InMemoryModelContainer.make()
        let env = Env(container: container, context: container.mainContext)

        let exercise = Exercise(name: "Bench Press")
        env.context.insert(exercise)
        let routine = Routine(name: "Push Day")
        let slot = RoutineExercise(exercise: exercise, order: 0)
        slot.routine = routine
        for order in 0..<2 {
            let set = ExerciseSet(reps: 12, weight: 60, restTime: 60, order: order)
            set.routineExercise = slot
            slot.sets?.append(set)
        }
        routine.routineExercises?.append(slot)
        env.context.insert(routine)
        try env.context.save()
        return (env, routine, slot)
    }

    /// Built as the WIRE intent and mapped through the real Data→Domain mapper,
    /// so these tests exercise the same boundary the coordinator uses rather
    /// than hand-constructing the Domain input.
    private func intent(
        slot: RoutineExercise, alternativeID: UUID? = nil,
        routineExerciseID: UUID? = nil,
        expectedWeight: Double = 60, proposedWeight: Double = 62.5,
        setIDs: [UUID]? = nil
    ) -> IncomingProgressiveOverload {
        let ids = setIDs ?? slot.setsList.map(\.id)
        return WatchProgressiveOverloadIntent(
            routineExerciseID: routineExerciseID ?? slot.id,
            alternativeID: alternativeID, targetRepMin: 8,
            setChanges: ids.map {
                WatchTemplateSetChange(
                    setID: $0, expectedReps: 12, expectedWeight: expectedWeight,
                    proposedReps: 8, proposedWeight: proposedWeight
                )
            }
        ).toIncomingProgressiveOverload()
    }

    @Test
    func appliesProposedValuesToEverySetAndCreatesNoHistory() throws {
        let (env, routine, slot) = try makeEnv()
        let (service, _) = env.makeService()

        let outcome = service.executeProgressiveOverload(intent(slot: slot), routineID: routine.id)
        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }

        let committed = try env.committedRoutine(routine.id)
        let sets = committed.routineExercisesList[0].setsList
        #expect(sets.allSatisfy { $0.reps == 8 && $0.weight == 62.5 })
        // A template-only transaction must never fabricate a workout.
        #expect(env.committedSessions().isEmpty)
    }

    @Test
    func reapplyingTheSameTransactionIsIdempotent() throws {
        let (env, routine, slot) = try makeEnv()
        let request = intent(slot: slot)

        let (first, _) = env.makeService()
        _ = first.executeProgressiveOverload(request, routineID: routine.id)
        let (second, _) = env.makeService()
        let outcome = second.executeProgressiveOverload(request, routineID: routine.id)

        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }
        let sets = try env.committedRoutine(routine.id).routineExercisesList[0].setsList
        // Not 65 — absolute values cannot increment twice.
        #expect(sets.allSatisfy { $0.weight == 62.5 })
    }

    @Test
    func aThirdValueRejectsTheWholeTransactionAndLeavesTheRoutineUntouched() throws {
        let (env, routine, slot) = try makeEnv()
        // The user edited ONE set on iPhone since the watch read the template.
        // `setsList` is the raw relationship array, so identify it by id rather
        // than position — SwiftData does not guarantee relationship order.
        let editedSetID = try #require(slot.setsList.first).id
        let untouchedSetID = try #require(slot.setsList.first { $0.id != editedSetID }).id
        try #require(slot.setsList.first { $0.id == editedSetID }).weight = 70
        try env.context.save()

        let (service, _) = env.makeService()
        let outcome = service.executeProgressiveOverload(intent(slot: slot), routineID: routine.id)
        guard case .rejected = outcome else { Issue.record("expected rejected, got \(outcome)"); return }

        let sets = try env.committedRoutine(routine.id).primarySets
        #expect(try #require(sets.first { $0.id == editedSetID }).weight == 70)
        // Partial application is forbidden: the conforming set is untouched too.
        #expect(try #require(sets.first { $0.id == untouchedSetID }).weight == 60)
        #expect(sets.allSatisfy { $0.reps == 12 })
    }

    @Test
    func aMissingSetRejectsTheWholeTransaction() throws {
        let (env, routine, slot) = try makeEnv()
        let (service, _) = env.makeService()

        let outcome = service.executeProgressiveOverload(
            intent(slot: slot, setIDs: [UUID()]), routineID: routine.id
        )
        guard case .rejected = outcome else { Issue.record("expected rejected, got \(outcome)"); return }
        #expect(try env.committedRoutine(routine.id).primarySets.allSatisfy { $0.weight == 60 })
    }

    @Test
    func aMissingSlotOrRoutineRejectsTerminally() throws {
        let (env, routine, slot) = try makeEnv()

        let (missingSlot, _) = env.makeService()
        let request = intent(slot: slot, routineExerciseID: UUID())
        guard case .rejected = missingSlot.executeProgressiveOverload(request, routineID: routine.id) else {
            Issue.record("expected rejection for a missing slot"); return
        }

        let (missingRoutine, _) = env.makeService()
        guard case .rejected = missingRoutine.executeProgressiveOverload(
            intent(slot: slot), routineID: UUID()
        ) else {
            Issue.record("expected rejection for a missing routine"); return
        }
    }

    @Test
    func anUnsupportedSchemaIsATerminalRejectionRatherThanSilentlyPending() throws {
        // The mapper is deliberately total: an unknown schema arrives as
        // `isSchemaSupported == false` so the receiver can still answer with a
        // versioned rejection instead of stranding the watch's transaction.
        let (env, routine, slot) = try makeEnv()
        var wire = WatchProgressiveOverloadIntent(
            routineExerciseID: slot.id, alternativeID: nil, targetRepMin: 8,
            setChanges: slot.setsList.map {
                WatchTemplateSetChange(
                    setID: $0.id, expectedReps: 12, expectedWeight: 60,
                    proposedReps: 8, proposedWeight: 62.5
                )
            }
        )
        wire.schemaVersion = WatchProgressiveOverloadIntent.currentSchemaVersion + 1
        let mapped = wire.toIncomingProgressiveOverload()
        #expect(!mapped.isSchemaSupported)
        #expect(!mapped.isWellFormed)

        let (service, _) = env.makeService()
        guard case .rejected = service.executeProgressiveOverload(mapped, routineID: routine.id) else {
            Issue.record("expected a terminal rejection for an unsupported schema"); return
        }
        #expect(try env.committedRoutine(routine.id).primarySets.allSatisfy { $0.weight == 60 })
    }

    @Test
    func alternativeIntentWritesOnlyIntoTheAlternativeScheme() throws {
        let (env, routine, slot) = try makeEnv()
        let altExercise = Exercise(name: "Incline Press")
        env.context.insert(altExercise)
        let alternative = RoutineExerciseAlternative(exercise: altExercise, order: 0)
        alternative.routineExercise = slot
        let altSet = AlternativeExerciseSet(reps: 12, weight: 40, restTime: 60, order: 0)
        altSet.alternative = alternative
        alternative.sets?.append(altSet)
        slot.alternatives?.append(alternative)
        try env.context.save()

        let (service, _) = env.makeService()
        let outcome = service.executeProgressiveOverload(
            intent(
                slot: slot, alternativeID: alternative.id,
                expectedWeight: 40, proposedWeight: 42.5, setIDs: [altSet.id]
            ),
            routineID: routine.id
        )
        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }

        let committed = try env.committedRoutine(routine.id).routineExercisesList[0]
        #expect(committed.alternativesList[0].setsList[0].weight == 42.5)
        #expect(committed.alternativesList[0].setsList[0].reps == 8)
        // The primary scheme must never receive an alternative's values.
        #expect(committed.setsList.allSatisfy { $0.weight == 60 && $0.reps == 12 })
    }

    @Test
    func unrelatedSlotsAndConcurrentEditsSurvive() throws {
        let (env, routine, slot) = try makeEnv()
        let other = Exercise(name: "Row")
        env.context.insert(other)
        let otherSlot = RoutineExercise(exercise: other, order: 1)
        otherSlot.routine = routine
        let otherSet = ExerciseSet(reps: 10, weight: 45, restTime: 60, order: 0)
        otherSet.routineExercise = otherSlot
        otherSlot.sets?.append(otherSet)
        routine.routineExercises?.append(otherSlot)
        try env.context.save()

        let (service, _) = env.makeService()
        _ = service.executeProgressiveOverload(intent(slot: slot), routineID: routine.id)

        let committed = try env.committedRoutine(routine.id)
        let untouched = try #require(committed.routineExercisesList.first { $0.id == otherSlot.id })
        #expect(untouched.setsList[0].weight == 45)
        #expect(untouched.setsList[0].reps == 10)
        #expect(committed.routineExercisesList.count == 2)
    }

    @Test
    func aLaterCompletedWorkoutCannotRegressAnOverloadResolvedTarget() throws {
        let (env, routine, slot) = try makeEnv()

        // 1. The overload transaction commits 8 × 62.5.
        let (overload, _) = env.makeService()
        _ = overload.executeProgressiveOverload(intent(slot: slot), routineID: routine.id)

        // 2. The completed workout replays the PERFORMED values for the same
        //    slot and would otherwise write 12 × 60 straight back over it.
        let performed = slot.setsList.map {
            Fixtures.makeSet(
                id: $0.id, plannedReps: 8, actualReps: 12, plannedWeight: 62.5, actualWeight: 60
            )
        }
        var workout = Fixtures.makeWorkout(
            routineId: routine.id, shouldUpdateTemplate: true,
            exercises: [Fixtures.makeExercise(id: slot.id, sets: performed)]
        )
        workout.overloadAppliedExerciseIDs = [slot.id]

        let (completion, _) = env.makeService()
        let outcome = completion.execute(workout.toIncomingWatchWorkout())
        guard case .applied = outcome else { Issue.record("expected applied, got \(outcome)"); return }

        let sets = try env.committedRoutine(routine.id).primarySets
        #expect(sets.allSatisfy { $0.weight == 62.5 && $0.reps == 8 },
                "the overload must survive the completed-workout writeback")
    }

    @Test
    func ingestMarksOnlyListedExercisesAsOverloadApplied() throws {
        let (env, routine, slot) = try makeEnv()
        let other = Exercise(name: "Row")
        env.context.insert(other)
        let otherSlot = RoutineExercise(exercise: other, order: 1)
        otherSlot.routine = routine
        routine.routineExercises?.append(otherSlot)
        try env.context.save()

        var workout = Fixtures.makeWorkout(
            routineId: routine.id, shouldUpdateTemplate: false,
            exercises: [
                Fixtures.makeExercise(id: slot.id, sets: [Fixtures.makeSet()]),
                Fixtures.makeExercise(id: otherSlot.id, sets: [Fixtures.makeSet()])
            ]
        )
        workout.overloadAppliedExerciseIDs = [slot.id]

        let (service, _) = env.makeService()
        _ = service.execute(workout.toIncomingWatchWorkout())

        let session = try #require(env.committedSessions().first)
        let marked = session.workoutExercisesList.filter(\.progressiveOverloadApplied)
        #expect(marked.count == 1)
        #expect(marked.first?.routineExerciseId == slot.id)
    }
}

private extension Routine {
    /// The first slot's sets. Callers must match by set id, not position —
    /// `RoutineExercise.setsList` is the raw relationship array and SwiftData
    /// does not guarantee its order.
    var primarySets: [ExerciseSet] {
        routineExercisesList.sorted { $0.order < $1.order }[0].setsList
    }
}
