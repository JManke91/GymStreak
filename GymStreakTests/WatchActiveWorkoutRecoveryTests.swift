//
//  WatchActiveWorkoutRecoveryTests.swift
//  GymStreakTests
//
//  Covers ticket 08 (in-workout routine editing) recovery of an active watch
//  workout after process termination. The watch has no unit-test target, so
//  these iOS-target tests stand in for the dual-copied logic:
//
//   • the pure crash-point classification (`WatchWorkoutRecoveryPlanner`),
//     including that active-session recovery is never treated as proof an
//     already-ended workout finished;
//   • the durable checkpoint round-trip with stable slot/set/workout IDs, swap
//     metadata, completion values, and structural provenance
//     (`WatchActiveWorkoutCheckpoint` + `WatchActiveWorkoutCheckpointStore`);
//   • corruption handling (undecodable → nil + `.corrupt` quarantine) and clear;
//   • the sync-state helper recovery inspects
//     (`interruptedFinalizationWorkoutIDs`).
//
//  The HealthKit reconnection, ViewModel resume, app-delegate wiring, and the
//  paired-hardware crash matrix are watch-only / device-only and are covered by
//  docs/watch-workout-recovery.md's hardware section, not here.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchActiveWorkoutRecoveryTests {
    private typealias Fixtures = WatchWorkoutSyncFixtures

    // MARK: - Fixtures

    private static func makeActiveExercise(
        slotID: UUID = UUID(),
        setID: UUID = UUID(),
        completed: Bool = false,
        pending: Bool = false,
        swapped: Bool = false
    ) -> ActiveWorkoutExercise {
        let set = ActiveWorkoutSet(
            id: setID,
            plannedReps: 10,
            actualReps: completed ? 12 : 10,
            plannedWeight: 60,
            actualWeight: completed ? 65 : 60,
            restTime: 90,
            completedAt: completed ? Date(timeIntervalSince1970: 1_700_000_300) : nil,
            order: 0
        )
        return ActiveWorkoutExercise(
            id: slotID,
            name: swapped ? "Incline Press" : "Bench Press",
            muscleGroup: "Chest",
            sets: [set],
            order: 0,
            supersetId: nil,
            supersetOrder: 0,
            targetRepMin: 8,
            targetRepMax: 12,
            exerciseId: UUID(),
            exerciseSeedKey: pending ? "bench-press" : nil,
            isPendingWatchAddition: pending,
            loadBehaviorRaw: "resistance",
            alternatives: [],
            plannedExerciseId: swapped ? UUID() : nil,
            plannedExerciseName: swapped ? "Bench Press" : nil
        )
    }

    private static func makeCheckpoint(
        workoutID: UUID = UUID(),
        healthKitID: UUID = UUID(),
        exercises: [ActiveWorkoutExercise]
    ) -> WatchActiveWorkoutCheckpoint {
        let routine = Fixtures.makeWatchRoutine(name: "Push Day")
        let baseline = WatchWorkoutStructuralBaseline(exercises: routine.exercises)
        return WatchActiveWorkoutCheckpoint(
            workoutID: workoutID,
            healthKitWorkoutID: healthKitID,
            routine: routine,
            exercises: exercises,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            structuralBaseline: baseline
        )
    }

    // MARK: - Planner (crash-point classification)

    @Test
    func planNoCheckpointNoEntryNoSessionIsNone() {
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: false, frozenEntryPhase: nil, didRecoverLiveSession: false
        ) == .none)
    }

    @Test
    func planActiveSessionWithoutCheckpointIsConstrainedOrphan() {
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: false, frozenEntryPhase: nil, didRecoverLiveSession: true
        ) == .constrainedOrphanSession)
    }

    @Test
    func planCheckpointWithLiveSessionResumesLiveWithMetrics() {
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: true, frozenEntryPhase: nil, didRecoverLiveSession: true
        ) == .resumeLiveWorkout(hasLiveSession: true))
    }

    @Test
    func planCheckpointWithoutLiveSessionResumesLiveConstrained() {
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: true, frozenEntryPhase: nil, didRecoverLiveSession: false
        ) == .resumeLiveWorkout(hasLiveSession: false))
    }

    @Test
    func planMidHealthKitPhasesResumeFinalization() {
        // A recovered live session in a HealthKit phase must resume finalization
        // (finish/end the session), never be treated as a finished workout.
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: true, frozenEntryPhase: .awaitingHealthKitMetadata, didRecoverLiveSession: true
        ) == .resumeFinalization(hasLiveSession: true))
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: false, frozenEntryPhase: .awaitingHealthKitMetadata, didRecoverLiveSession: false
        ) == .resumeFinalization(hasLiveSession: false))
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: true, frozenEntryPhase: .awaitingHealthKitFinish, didRecoverLiveSession: false
        ) == .resumeFinalization(hasLiveSession: false))
    }

    @Test
    func planPastHealthKitPhasesFinalizationCompleteOrNone() {
        // Finalization already advanced past HealthKit; only a stale checkpoint
        // needs cleanup, and no checkpoint means nothing to do.
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: true, frozenEntryPhase: .transportEligible, didRecoverLiveSession: false
        ) == .finalizationComplete)
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: false, frozenEntryPhase: .transportEligible, didRecoverLiveSession: false
        ) == .none)
        #expect(WatchWorkoutRecoveryPlanner.plan(
            hasCheckpoint: true, frozenEntryPhase: .quarantined, didRecoverLiveSession: false
        ) == .finalizationComplete)
    }

    // MARK: - Checkpoint round-trip + store

    @Test
    func checkpointRoundTripPreservesStableIdsSwapAndProvenance() throws {
        let slotID = UUID()
        let setID = UUID()
        let exercise = Self.makeActiveExercise(
            slotID: slotID, setID: setID, completed: true, pending: true, swapped: true
        )
        let original = Self.makeCheckpoint(exercises: [exercise])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchActiveWorkoutCheckpoint.self, from: data)

        // Full value equality proves every field round-trips.
        #expect(decoded == original)
        // Spell out the crash-critical identities and values explicitly.
        #expect(decoded.workoutID == original.workoutID)
        #expect(decoded.healthKitWorkoutID == original.healthKitWorkoutID)
        #expect(decoded.exercises.first?.id == slotID)
        #expect(decoded.exercises.first?.sets.first?.id == setID)
        #expect(decoded.exercises.first?.sets.first?.isCompleted == true)
        #expect(decoded.exercises.first?.sets.first?.actualReps == 12)
        #expect(decoded.exercises.first?.isPendingWatchAddition == true)
        #expect(decoded.exercises.first?.wasSwapped == true)
        #expect(decoded.structuralBaseline == original.structuralBaseline)
    }

    @Test
    func storeSaveLoadClearRoundTrip() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchActiveWorkoutCheckpointStore(directory: dir)

        #expect(store.load() == nil)
        #expect(store.hasCheckpoint == false)

        let checkpoint = Self.makeCheckpoint(exercises: [Self.makeActiveExercise(completed: true)])
        try store.save(checkpoint)

        #expect(store.hasCheckpoint == true)
        #expect(store.load() == checkpoint)

        // A reopened store reads the same durable bytes (relaunch).
        let reopened = WatchActiveWorkoutCheckpointStore(directory: dir)
        #expect(reopened.load() == checkpoint)

        store.clear()
        #expect(store.hasCheckpoint == false)
        #expect(store.load() == nil)
    }

    @Test
    func storeQuarantinesUndecodableCheckpointAndReportsNil() throws {
        let dir = try Fixtures.makeTempDirectory()
        let fileURL = dir.appendingPathComponent("active-workout-checkpoint.json")
        try Data("not a checkpoint".utf8).write(to: fileURL)

        let store = WatchActiveWorkoutCheckpointStore(directory: dir)

        // Missing/corrupt checkpoint reads as nil without discarding evidence.
        #expect(store.load() == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
        // The corrupt original is moved aside, never left to be re-read.
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    // MARK: - Interrupted-finalization inspection

    @Test
    func interruptedFinalizationWorkoutIDsReturnsHealthKitPhasesInFIFOOrder() throws {
        let dir = try Fixtures.makeTempDirectory()
        let store = WatchSyncStateStore(directory: dir, legacyDefaults: nil)

        let awaitingMetadata = Fixtures.makeWorkout()
        let awaitingFinish = Fixtures.makeWorkout()
        let eligible = Fixtures.makeWorkout()
        let quarantinedWorkout = Fixtures.makeWorkout()

        try store.enqueue(awaitingMetadata, phase: .awaitingHealthKitMetadata)
        try store.enqueue(awaitingFinish, phase: .awaitingHealthKitFinish)
        try store.enqueue(eligible, phase: .transportEligible)
        try store.enqueue(quarantinedWorkout, phase: .transportEligible)
        store.quarantine(id: quarantinedWorkout.id, reason: "test")

        // Only the two HealthKit-phase entries, oldest first.
        #expect(store.interruptedFinalizationWorkoutIDs() == [awaitingMetadata.id, awaitingFinish.id])
    }
}
