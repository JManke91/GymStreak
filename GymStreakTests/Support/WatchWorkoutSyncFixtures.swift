//
//  WatchWorkoutSyncFixtures.swift
//  GymStreakTests
//
//  Shared builders and temp-directory helpers for the ticket-04 watch
//  workout sync reliability tests (outgoing queue, finalizer, inbox,
//  receipts, ingestion coordinator).
//

import Foundation
@testable import GymStreak

enum WatchWorkoutSyncFixtures {
    static func makeWorkout(
        id: UUID = UUID(),
        routineId: UUID = UUID(),
        routineName: String = "Push Day",
        shouldUpdateTemplate: Bool = false,
        healthKitWorkoutId: UUID? = UUID(),
        exercises: [CompletedWatchExercise] = [],
        endTime: Date = Date(timeIntervalSince1970: 1_700_000_600),
        transactionID: UUID? = nil,
        senderEpoch: UUID? = nil,
        sequence: UInt64? = nil
    ) -> CompletedWatchWorkout {
        CompletedWatchWorkout(
            id: id,
            routineId: routineId,
            routineName: routineName,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: endTime,
            exercises: exercises,
            shouldUpdateTemplate: shouldUpdateTemplate,
            healthKitWorkoutId: healthKitWorkoutId,
            templateTransactionID: transactionID,
            templateSenderEpoch: senderEpoch,
            templateSequence: sequence
        )
    }

    /// A watch routine with one exercise and one set, matching the ids a
    /// completed-workout payload references.
    static func makeWatchRoutine(
        id: UUID = UUID(),
        name: String = "Push Day",
        exerciseId: UUID = UUID(),
        setId: UUID = UUID(),
        reps: Int = 10,
        weight: Double = 60
    ) -> WatchRoutine {
        WatchRoutine(
            id: id,
            name: name,
            exercises: [WatchExercise(
                id: exerciseId,
                name: "Bench Press",
                muscleGroup: "Chest",
                sets: [WatchSet(id: setId, reps: reps, weight: weight, restTime: 60)],
                order: 0,
                supersetId: nil,
                supersetOrder: 0
            )]
        )
    }

    static func makeExercise(
        id: UUID = UUID(),
        exerciseId: UUID = UUID(),
        name: String = "Bench Press",
        sets: [CompletedWatchSet]
    ) -> CompletedWatchExercise {
        CompletedWatchExercise(
            id: id,
            name: name,
            muscleGroup: "Chest",
            sets: sets,
            order: 0,
            supersetId: nil,
            supersetOrder: 0,
            targetRepMin: nil,
            targetRepMax: nil,
            exerciseId: exerciseId,
            loadBehaviorRaw: "resistance",
            plannedExerciseId: nil,
            plannedExerciseName: nil
        )
    }

    static func makeSet(
        id: UUID = UUID(),
        plannedReps: Int = 10,
        actualReps: Int = 10,
        plannedWeight: Double = 60,
        actualWeight: Double = 60,
        order: Int = 0
    ) -> CompletedWatchSet {
        CompletedWatchSet(
            id: id,
            plannedReps: plannedReps,
            actualReps: actualReps,
            plannedWeight: plannedWeight,
            actualWeight: actualWeight,
            restTime: 60,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 1_700_000_300),
            order: order
        )
    }

    /// The template half a template-carrying workout's enqueue produced
    /// (ADR 0001). It is not reachable through `entry(id:)`, whose match is the
    /// workout id the history half owns, so tests look it up by the workout
    /// wrapped inside the transaction.
    @MainActor
    static func templateEntry(
        in store: WatchSyncStateStore, forWorkout workoutID: UUID
    ) -> OutgoingSyncEntry? {
        store.all.first { $0.templateTransaction?.templateIntentWorkout?.id == workoutID }
    }

    /// Fresh temp directory per test.
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Fresh, isolated UserDefaults suite per test (caller must remove it).
    static func makeDefaultsSuite() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "watch-sync-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    /// Makes a directory unwritable (owner write bit off) so atomic writes
    /// into it fail. Returns a closure restoring write permission.
    static func makeReadOnly(_ directory: URL) throws -> () -> Void {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: directory.path
        )
        return {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.path
            )
        }
    }
}
