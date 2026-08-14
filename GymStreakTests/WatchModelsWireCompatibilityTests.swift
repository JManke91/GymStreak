//
//  WatchModelsWireCompatibilityTests.swift
//  GymStreakTests
//
//  iOS-side twin of `GymStreakWatchTests/WatchModelsWireCompatibilityTests.swift`.
//  `WatchModels.swift` is duplicated per target and carries the WatchConnectivity
//  wire schema, so a field that is non-optional in only one copy compiles cleanly
//  on both and fails at runtime — exactly the drift audit item P1.4 found in
//  `CompletedWatchExercise.loadBehaviorRaw`.
//
//  The invariant pinned here: every field added to the wire schema after v1 must
//  be Optional, because synthesized `Decodable` does NOT fall back to a stored
//  property's default value — an absent key throws `keyNotFound` and fails the
//  whole payload. iOS is the receiver, so this is its tolerance contract.
//
//  Assertions are kept aligned with the watch twin so a re-drift fails on one side.
//

import Foundation
import Testing
@testable import GymStreak

struct WatchModelsWireCompatibilityTests {

    /// Only the fields that existed in the original schema. Every later addition
    /// is absent, which is what a payload encoded by an older watch build looks like.
    private static let minimalPayload = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "routineId": "00000000-0000-0000-0000-000000000002",
      "routineName": "Push",
      "startTime": 0,
      "endTime": 3600,
      "shouldUpdateTemplate": false,
      "exercises": [
        {
          "id": "00000000-0000-0000-0000-000000000003",
          "name": "Bench Press",
          "muscleGroup": "Chest",
          "order": 0,
          "supersetOrder": 0,
          "sets": [
            {
              "id": "00000000-0000-0000-0000-000000000004",
              "plannedReps": 10,
              "actualReps": 10,
              "plannedWeight": 60,
              "actualWeight": 60,
              "restTime": 90,
              "isCompleted": true,
              "order": 0
            }
          ]
        }
      ]
    }
    """

    @Test
    func completedWorkoutDecodesWhenEveryPostV1FieldIsAbsent() throws {
        let workout = try JSONDecoder().decode(
            CompletedWatchWorkout.self,
            from: Data(Self.minimalPayload.utf8)
        )

        #expect(workout.routineName == "Push")
        #expect(workout.healthKitWorkoutId == nil)
        #expect(workout.templateTransactionID == nil)
        #expect(workout.addedRoutineExerciseIDs == nil)
        #expect(workout.overloadAppliedExerciseIDs == nil)

        let exercise = try #require(workout.exercises.first)
        #expect(exercise.loadBehaviorRaw == nil)
        #expect(exercise.exerciseSeedKey == nil)
        #expect(exercise.targetRepMin == nil)
        #expect(exercise.plannedExerciseId == nil)

        let set = try #require(exercise.sets.first)
        #expect(set.plannedRestTime == nil)
        #expect(set.wasRestAdjusted == false)
    }

    /// An absent `loadBehaviorRaw` resolves to resistance at the Data→Domain
    /// boundary, so nothing downstream of the wire ever sees the ambiguity.
    @Test
    func absentLoadBehaviorResolvesToResistanceAtTheDomainBoundary() throws {
        let workout = try JSONDecoder().decode(
            CompletedWatchWorkout.self,
            from: Data(Self.minimalPayload.utf8)
        )
        let incoming = workout.toIncomingWatchWorkout()
        let exercise = try #require(incoming.exercises.first)

        #expect(exercise.loadBehaviorRaw == ExerciseLoadBehavior.resistance.rawValue)
    }

    /// A present value survives the round trip unchanged — tolerance must not
    /// come at the cost of dropping the field the watch actually sends.
    @Test
    func presentLoadBehaviorSurvivesTheRoundTrip() throws {
        let sent = CompletedWatchExercise(
            id: UUID(),
            name: "Assisted Pull Up",
            muscleGroup: "Lats",
            sets: [],
            order: 0,
            supersetId: nil,
            supersetOrder: 0,
            loadBehaviorRaw: ExerciseLoadBehavior.counterweightAssistance.rawValue
        )

        let decoded = try JSONDecoder().decode(
            CompletedWatchExercise.self,
            from: try JSONEncoder().encode(sent)
        )

        #expect(decoded.loadBehaviorRaw == ExerciseLoadBehavior.counterweightAssistance.rawValue)
        #expect(
            decoded.toIncomingWatchExercise().loadBehaviorRaw
                == ExerciseLoadBehavior.counterweightAssistance.rawValue
        )
    }

    // MARK: - Checkpoint schema (ActiveWorkoutExercise)

    /// `ActiveWorkoutExercise` keeps three non-optional post-v1 fields, so it
    /// carries a hand-written `init(from:)` instead (widening them would ripple
    /// through every read site in `WatchWorkoutViewModel`). A checkpoint written
    /// before those fields existed must still restore rather than throw.
    @Test
    func checkpointExerciseDecodesWhenPostV1FieldsAreAbsent() throws {
        let legacy = """
        {
          "id": "00000000-0000-0000-0000-000000000005",
          "name": "Bench Press",
          "muscleGroup": "Chest",
          "sets": [],
          "order": 0,
          "supersetOrder": 0
        }
        """

        let exercise = try JSONDecoder().decode(
            ActiveWorkoutExercise.self,
            from: Data(legacy.utf8)
        )

        #expect(exercise.loadBehaviorRaw == "resistance")
        #expect(exercise.isPendingWatchAddition == false)
        #expect(exercise.alternatives.isEmpty)
    }

    /// Guards the hand-written `init(from:)`: a stored property added later but
    /// not decoded there still compiles, and then silently never restores. Two
    /// halves are needed — see the comments inside.
    @Test
    func checkpointExerciseRoundTripPreservesEveryField() throws {
        let original = ActiveWorkoutExercise(
            id: UUID(),
            name: "Assisted Pull Up",
            muscleGroup: "Lats",
            sets: [
                ActiveWorkoutSet(
                    id: UUID(),
                    plannedReps: 8,
                    actualReps: 9,
                    plannedWeight: 20,
                    actualWeight: 22.5,
                    restTime: 75,
                    plannedRestTime: 90,
                    completedAt: Date(timeIntervalSince1970: 1),
                    order: 3
                )
            ],
            order: 4,
            supersetId: UUID(),
            supersetOrder: 2,
            targetRepMin: 6,
            targetRepMax: 12,
            exerciseId: UUID(),
            exerciseSeedKey: "seed.assisted_pull_up",
            isPendingWatchAddition: true,
            loadBehaviorRaw: "counterweightAssistance",
            alternatives: [
                WatchExerciseAlternative(
                    id: UUID(),
                    exerciseId: UUID(),
                    name: "Lat Pulldown",
                    muscleGroup: "Lats",
                    sets: [],
                    order: 1,
                    loadBehaviorRaw: "resistance",
                    targetRepMin: 8,
                    targetRepMax: 10
                )
            ],
            plannedExerciseId: UUID(),
            plannedExerciseName: "Pull Up",
            originalMuscleGroup: "Back",
            originalLoadBehaviorRaw: "resistance",
            originalSets: [WatchSet(id: UUID(), reps: 5, weight: 0, restTime: 60)],
            originalTargetRepMin: 5,
            originalTargetRepMax: 8
        )

        let encoded = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        // Structural half: `encode(to:)` stays synthesized, so a newly added
        // stored property changes this key set. Pinning it — and the stored
        // property count, which also catches an Optional addition the fixture
        // above forgot to populate — is what forces a visit to `init(from:)`.
        // Value equality alone would not: a new defaulted property left out of
        // both the fixture and the init lands on its default on both sides.
        let expectedKeys: Set<String> = [
            "id", "name", "muscleGroup", "sets", "order", "supersetId", "supersetOrder",
            "targetRepMin", "targetRepMax", "exerciseId", "exerciseSeedKey",
            "isPendingWatchAddition", "loadBehaviorRaw", "alternatives",
            "plannedExerciseId", "plannedExerciseName", "originalMuscleGroup",
            "originalLoadBehaviorRaw", "originalSets", "originalTargetRepMin",
            "originalTargetRepMax",
        ]
        #expect(Set(object.keys) == expectedKeys)
        #expect(Mirror(reflecting: original).children.count == expectedKeys.count)

        // Value half: every field above is at a non-default value, so a field
        // decoded incorrectly (rather than not at all) fails here.
        let decoded = try JSONDecoder().decode(ActiveWorkoutExercise.self, from: encoded)
        #expect(decoded == original)
    }

    /// The containing type had the same hazard one level up: `appliedOverloads`
    /// and `deferredOverloadSlotIDs` were non-optional with defaults, added in
    /// `4f82e33` after the 1.1.6 checkpoint shape had already shipped. A throw
    /// here is not a partial loss — `WatchActiveWorkoutCheckpointStore.load()`
    /// quarantines the file and returns nil, so the recovery planner sees no
    /// checkpoint and the user's live workout is discarded.
    @Test
    func checkpointDecodesWhenPostV1FieldsAreAbsent() throws {
        let checkpoint = WatchActiveWorkoutCheckpoint(
            workoutID: UUID(),
            healthKitWorkoutID: UUID(),
            routine: WatchRoutine(id: UUID(), name: "Push", exercises: []),
            exercises: [],
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            startTime: Date(timeIntervalSince1970: 1),
            structuralBaseline: WatchWorkoutStructuralBaseline(exercises: [])
        )

        var object = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(checkpoint))
                as? [String: Any]
        )
        // Structural pin, same reasoning as the exercise-level guard above: a
        // future non-optional field added HERE reproduces the original bug, and
        // only a key-set assertion notices. Also guards against these two keys
        // being renamed out from under the strip below.
        let expectedKeys: Set<String> = [
            "version", "workoutID", "healthKitWorkoutID", "routine", "exercises",
            "currentExerciseIndex", "currentSetIndex", "startTime",
            "structuralBaseline", "appliedOverloads", "deferredOverloadSlotIDs",
        ]
        #expect(Set(object.keys) == expectedKeys)
        #expect(Mirror(reflecting: checkpoint).children.count == expectedKeys.count)

        object.removeValue(forKey: "appliedOverloads")
        object.removeValue(forKey: "deferredOverloadSlotIDs")

        let decoded = try JSONDecoder().decode(
            WatchActiveWorkoutCheckpoint.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.appliedOverloads == nil)
        #expect(decoded.deferredOverloadSlotIDs == nil)
        #expect(decoded.workoutID == checkpoint.workoutID)
    }
}
