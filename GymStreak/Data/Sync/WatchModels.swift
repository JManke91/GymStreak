import Foundation

// MARK: - Lightweight models for Watch app
// These are Codable structs used for syncing between iOS and watchOS
// This file is shared between iOS and Watch targets

struct WatchRoutine: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let exercises: [WatchExercise]

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var exerciseCount: Int {
        exercises.count
    }
}

struct WatchExercise: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let sets: [WatchSet]
    let order: Int
    let supersetId: UUID?
    let supersetOrder: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    var exerciseSeedKey: String? = nil
    var isPendingWatchAddition: Bool? = nil
    var loadBehaviorRaw: String? = nil
    // Optional (nil default) keeps old cached payloads decodable.
    var alternatives: [WatchExerciseAlternative]? = nil
}

struct WatchSet: Codable, Identifiable, Hashable {
    let id: UUID
    let reps: Int
    let weight: Double
    let restTime: TimeInterval
}

/// An alternative exercise a user can swap to during a workout (with its own set scheme).
struct WatchExerciseAlternative: Codable, Identifiable, Hashable {
    let id: UUID          // RoutineExerciseAlternative.id
    let exerciseId: UUID  // the alternative Exercise's id
    let name: String
    let muscleGroup: String
    let sets: [WatchSet]
    let order: Int
    var loadBehaviorRaw: String? = nil
    /// The alternative's OWN rep-range goal, independent of the primary slot's
    /// (progressive-overload ticket 04). Optional so cached snapshots produced
    /// before this field existed stay decodable; the watch captures/restores the
    /// primary range on swap and adopts these values while the swap is active,
    /// so a swapped exercise qualifies against the range it was actually
    /// performed under.
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
}

// MARK: - Active workout structural state

/// Duplicated in the watch target so the pure structural reducer can be
/// exercised by the existing iOS unit-test target without adding SwiftUI or
/// WatchKit dependencies to the test seam.
struct ActiveWorkoutExercise: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var muscleGroup: String
    var sets: [ActiveWorkoutSet]
    var order: Int
    var supersetId: UUID?
    var supersetOrder: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    var exerciseSeedKey: String? = nil
    var isPendingWatchAddition: Bool = false
    var loadBehaviorRaw: String = "resistance"
    var alternatives: [WatchExerciseAlternative] = []
    var plannedExerciseId: UUID? = nil
    var plannedExerciseName: String? = nil
    var originalMuscleGroup: String? = nil
    var originalLoadBehaviorRaw: String? = nil
    var originalSets: [WatchSet]? = nil
    // Captured on first swap alongside the other original identity, so reverting
    // restores the primary slot's own rep-range goal (ticket 04). While a swap
    // is active the exercise adopts the ALTERNATIVE's range, which is what the
    // overload suggestion must qualify against — the user performed that range.
    var originalTargetRepMin: Int? = nil
    var originalTargetRepMax: Int? = nil

    var completedSetsCount: Int { sets.filter(\.isCompleted).count }
    var isComplete: Bool { sets.allSatisfy(\.isCompleted) }
    var isInSuperset: Bool { supersetId != nil }
    var wasSwapped: Bool { plannedExerciseId != nil }
    var canSwap: Bool { completedSetsCount == 0 && !alternatives.isEmpty }
    var hasRepRangeGoal: Bool { targetRepMin != nil && targetRepMax != nil }

    var allCompletedSetsAtUpperLimit: Bool {
        guard let max = targetRepMax, !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.isCompleted && $0.actualReps >= max }
    }
}

/// Hand-written so a `WatchActiveWorkoutCheckpoint` persisted by an older build
/// stays decodable. Synthesized `Decodable` emits a plain `decode` for the three
/// non-optional post-v1 fields below and throws `keyNotFound` when an older
/// checkpoint lacks them — a stored property's default value is NOT a
/// decode-time fallback (`docs/watch-sync.md`, "Wire schema evolution rule").
/// This is the alternative to widening those fields to Optional, which would
/// have rippled through every read site in `WatchWorkoutViewModel`.
///
/// Deliberately in an EXTENSION: an `init` in the struct body would suppress the
/// memberwise initializer every construction site uses. `CodingKeys` and
/// `encode(to:)` stay synthesized, so a newly added property can never be
/// silently dropped from the encoded form.
///
/// MAINTENANCE: a new stored property must be decoded here too. One with a
/// default value compiles without it and then silently never restores, and the
/// compiler cannot flag that. `checkpointExerciseRoundTripPreservesEveryField`
/// is the guard: it pins the encoded key set and the stored-property count, so
/// adding a property fails it whether or not the property has a default.
extension ActiveWorkoutExercise {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        muscleGroup = try container.decode(String.self, forKey: .muscleGroup)
        sets = try container.decode([ActiveWorkoutSet].self, forKey: .sets)
        order = try container.decode(Int.self, forKey: .order)
        supersetId = try container.decodeIfPresent(UUID.self, forKey: .supersetId)
        supersetOrder = try container.decode(Int.self, forKey: .supersetOrder)
        targetRepMin = try container.decodeIfPresent(Int.self, forKey: .targetRepMin)
        targetRepMax = try container.decodeIfPresent(Int.self, forKey: .targetRepMax)
        exerciseId = try container.decodeIfPresent(UUID.self, forKey: .exerciseId)
        exerciseSeedKey = try container.decodeIfPresent(String.self, forKey: .exerciseSeedKey)
        // Post-v1 and non-optional: absent means the checkpoint predates the field.
        isPendingWatchAddition =
            try container.decodeIfPresent(Bool.self, forKey: .isPendingWatchAddition) ?? false
        loadBehaviorRaw =
            try container.decodeIfPresent(String.self, forKey: .loadBehaviorRaw) ?? "resistance"
        alternatives =
            try container.decodeIfPresent([WatchExerciseAlternative].self, forKey: .alternatives) ?? []
        plannedExerciseId = try container.decodeIfPresent(UUID.self, forKey: .plannedExerciseId)
        plannedExerciseName = try container.decodeIfPresent(String.self, forKey: .plannedExerciseName)
        originalMuscleGroup = try container.decodeIfPresent(String.self, forKey: .originalMuscleGroup)
        originalLoadBehaviorRaw =
            try container.decodeIfPresent(String.self, forKey: .originalLoadBehaviorRaw)
        originalSets = try container.decodeIfPresent([WatchSet].self, forKey: .originalSets)
        originalTargetRepMin = try container.decodeIfPresent(Int.self, forKey: .originalTargetRepMin)
        originalTargetRepMax = try container.decodeIfPresent(Int.self, forKey: .originalTargetRepMax)
    }
}

struct ActiveWorkoutSet: Identifiable, Equatable, Codable {
    let id: UUID
    var plannedReps: Int
    var actualReps: Int
    var plannedWeight: Double
    var actualWeight: Double
    var restTime: TimeInterval
    /// The rest time this set started the workout with (ticket 04, rest in the
    /// template transaction). `restTime` is mutated in place by a Crown
    /// adjustment, so without a baseline a rest-only change is invisible to the
    /// template-change detection.
    ///
    /// Optional, and nil means "no baseline recorded" (never rest intent): a
    /// checkpoint written before this field existed stays decodable.
    var plannedRestTime: TimeInterval? = nil
    var completedAt: Date?
    var order: Int

    var isCompleted: Bool { completedAt != nil }
    var wasModified: Bool {
        actualReps != plannedReps || actualWeight != plannedWeight
    }

    /// Deliberately NOT part of `wasModified`: a rest change is one change per
    /// exercise, not per set, and folding it in would inflate the "you modified
    /// N sets" count on the finish dialog.
    var wasRestAdjusted: Bool {
        guard let plannedRestTime else { return false }
        return restTime != plannedRestTime
    }
}

// MARK: - Completed Workout for syncing back to iOS

struct CompletedWatchWorkout: Codable {
    let id: UUID
    let routineId: UUID
    let routineName: String
    let startTime: Date
    let endTime: Date
    let exercises: [CompletedWatchExercise]
    let shouldUpdateTemplate: Bool
    /// The UUID used as HKMetadataKeyExternalUUID when saving to HealthKit.
    /// Used to correlate SwiftData WorkoutSession with HealthKit workout.
    let healthKitWorkoutId: UUID?

    // Template-transaction ordering identity (ticket 05). Optional (nil
    // default) keeps old payloads decodable. Assigned by the watch sync-state
    // owner in the same atomic commit as the enqueue, only when
    // `shouldUpdateTemplate == true`; stable across retries. The transaction
    // ID is the semantic transaction identity; the workout id is correlation.
    var templateTransactionID: UUID? = nil
    /// Persistent watch sender epoch shared by every template-mutating kind.
    var templateSenderEpoch: UUID? = nil
    /// Monotonic per-routine sequence within `templateSenderEpoch`.
    var templateSequence: UInt64? = nil

    // Explicit structural membership intent (ticket 07). Optional (nil default)
    // keeps old payloads decodable; the Data→Domain mapper normalizes absence
    // to empty. Additions are emitted in final exercise order and identify a
    // minted slot present in `exercises`; removals are emitted in workout-start
    // baseline order and are absent from `exercises`. When
    // `shouldUpdateTemplate == false` these are historical metadata only and
    // never mutate a routine.
    var addedRoutineExerciseIDs: [UUID]? = nil
    var removedRoutineExerciseIDs: [UUID]? = nil

    /// Slot IDs whose target had progressive overload applied during this
    /// workout (ticket 04). Optional (nil default) keeps old payloads
    /// decodable. Two jobs, both required for correctness:
    ///
    /// 1. iOS sets `WorkoutExercise.progressiveOverloadApplied` for these, which
    ///    switches every aggregator (volume, charts, records, AI Coach) to read
    ///    the `planned*` values — where the watch has mirrored the true
    ///    performance, exactly as `WorkoutViewModel.applyProgressiveOverload`
    ///    does. Neither platform writes the increase into `actual*`: it is the
    ///    next workout's target, not this workout's work.
    /// 2. Both the watch fold and the iOS merge exclude these exercises from
    ///    generic set-value writeback, so this completed-workout transaction
    ///    cannot overwrite the template weights the overload transaction
    ///    already committed. Structural intent is unaffected.
    var overloadAppliedExerciseIDs: [UUID]? = nil

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var hasModifiedSets: Bool {
        exercises.contains { exercise in
            exercise.sets.contains { set in
                set.actualReps != set.plannedReps || set.actualWeight != set.plannedWeight
            }
        }
    }

    var modifiedSetsCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter { set in
                set.actualReps != set.plannedReps || set.actualWeight != set.plannedWeight
            }.count
        }
    }

    /// Slots whose rest duration the watch changed during this workout.
    var restAdjustedExerciseIDs: [UUID] {
        exercises.filter { $0.sets.contains(where: \.wasRestAdjusted) }.map(\.id)
    }

    /// The history half of a split workout (ADR 0001): the same performance
    /// record with the template intent and its ordering identity removed, so it
    /// travels as an ordinary workout payload — ungated by the routine's
    /// transaction queue, retired by the plain acknowledgment, and understood by
    /// iOS builds that predate the split. Keeping the intent here would make iOS
    /// route it back into the template path and consume the same sequence twice.
    ///
    /// Structural and applied-overload slot IDs are retained: with
    /// `shouldUpdateTemplate == false` they are historical metadata that never
    /// mutates a routine, and iOS needs them to record the workout correctly.
    func withoutTemplateIntent() -> CompletedWatchWorkout {
        CompletedWatchWorkout(
            id: id,
            routineId: routineId,
            routineName: routineName,
            startTime: startTime,
            endTime: endTime,
            exercises: exercises,
            shouldUpdateTemplate: false,
            healthKitWorkoutId: healthKitWorkoutId,
            addedRoutineExerciseIDs: addedRoutineExerciseIDs,
            removedRoutineExerciseIDs: removedRoutineExerciseIDs,
            overloadAppliedExerciseIDs: overloadAppliedExerciseIDs
        )
    }
}

struct CompletedWatchExercise: Codable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let sets: [CompletedWatchSet]
    let order: Int
    let supersetId: UUID?
    let supersetOrder: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var exerciseId: UUID? = nil
    /// Stable seeded-library fallback identity (ticket 07). Carried so iOS can
    /// resolve a Watch-added exercise by seed key when its `exerciseId` no
    /// longer resolves (e.g. seed-dedup changed the surviving row's UUID).
    var exerciseSeedKey: String? = nil
    /// Optional (nil default) keeps payloads that predate the field decodable.
    /// Synthesized `Decodable` does NOT fall back to a stored property's default
    /// value — an absent key throws `keyNotFound` and takes the whole payload
    /// (on the watch, the whole persisted queue) with it. Absent means "unknown";
    /// both sides resolve that to `.resistance` at the point of use.
    var loadBehaviorRaw: String? = nil
    // Set only when the exercise was swapped for an alternative during the workout.
    // name/muscleGroup/exerciseId describe what was actually performed.
    var plannedExerciseId: UUID? = nil
    var plannedExerciseName: String? = nil
}

struct CompletedWatchSet: Codable {
    let id: UUID
    let plannedReps: Int
    let actualReps: Int
    let plannedWeight: Double
    let actualWeight: Double
    let restTime: TimeInterval
    let isCompleted: Bool
    let completedAt: Date?
    let order: Int
    /// The rest time the set started the workout with (ticket 04, rest in the
    /// template transaction). `restTime` carries what was actually rested for;
    /// the pair is what makes a rest change *explicit intent*, exactly as
    /// `plannedReps`/`actualReps` do for values — without it iOS would have to
    /// guess by diffing against the live template and would silently revert a
    /// concurrent iPhone edit. Optional (nil default) keeps old payloads
    /// decodable; nil is simply "no rest intent".
    var plannedRestTime: TimeInterval? = nil

    /// The watch explicitly changed this set's rest during the workout. The
    /// single definition of rest intent on the wire — the optimistic fold and
    /// the finalization diagnostics both read it, and the iOS merge applies the
    /// same rule to its Domain twin.
    var wasRestAdjusted: Bool {
        guard let plannedRestTime else { return false }
        return restTime != plannedRestTime
    }
}

// MARK: - Wire DTO to Domain ingestion input

// Maps the decoded WatchConnectivity wire DTOs into the Domain-owned
// `IncomingWatchWorkout` model, keeping `CompletedWatchWorkout` (and its nested
// types) out of the Domain layer. Called at the WatchConnectivity boundary in
// `WatchConnectivityManager` before the payload reaches Domain/Presentation.

extension CompletedWatchWorkout {
    func toIncomingWatchWorkout() -> IncomingWatchWorkout {
        IncomingWatchWorkout(
            id: id,
            routineId: routineId,
            routineName: routineName,
            startTime: startTime,
            endTime: endTime,
            exercises: exercises.map { $0.toIncomingWatchExercise() },
            shouldUpdateTemplate: shouldUpdateTemplate,
            healthKitWorkoutId: healthKitWorkoutId,
            templateTransactionID: templateTransactionID,
            templateSenderEpoch: templateSenderEpoch,
            templateSequence: templateSequence,
            addedRoutineExerciseIDs: addedRoutineExerciseIDs ?? [],
            removedRoutineExerciseIDs: removedRoutineExerciseIDs ?? [],
            overloadAppliedExerciseIDs: overloadAppliedExerciseIDs ?? []
        )
    }
}

extension CompletedWatchExercise {
    func toIncomingWatchExercise() -> IncomingWatchExercise {
        IncomingWatchExercise(
            id: id,
            name: name,
            muscleGroup: muscleGroup,
            sets: sets.map { $0.toIncomingWatchSet() },
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            exerciseId: exerciseId,
            exerciseSeedKey: exerciseSeedKey,
            loadBehaviorRaw: loadBehaviorRaw ?? ExerciseLoadBehavior.resistance.rawValue,
            plannedExerciseId: plannedExerciseId,
            plannedExerciseName: plannedExerciseName
        )
    }
}

extension CompletedWatchSet {
    func toIncomingWatchSet() -> IncomingWatchSet {
        IncomingWatchSet(
            id: id,
            plannedReps: plannedReps,
            actualReps: actualReps,
            plannedWeight: plannedWeight,
            actualWeight: actualWeight,
            restTime: restTime,
            isCompleted: isCompleted,
            completedAt: completedAt,
            order: order,
            plannedRestTime: plannedRestTime
        )
    }
}

// MARK: - SwiftData to Watch Model Conversion

extension Routine {
    func toWatchRoutine() -> WatchRoutine {
        let sortedExercises = routineExercisesList.sorted { $0.order < $1.order }
        return WatchRoutine(
            id: id,
            name: name,
            exercises: sortedExercises.map { routineExercise in
                WatchExercise(
                    id: routineExercise.id,
                    name: routineExercise.exercise?.name ?? "Unknown",
                    muscleGroup: routineExercise.exercise?.primaryMuscleGroup ?? "General",
                    sets: routineExercise.setsList.sorted(by: { $0.order < $1.order }).map { set in
                        WatchSet(
                            id: set.id,
                            reps: set.reps,
                            weight: set.weight,
                            restTime: set.restTime
                        )
                    },
                    order: routineExercise.order,
                    supersetId: routineExercise.supersetId,
                    supersetOrder: routineExercise.supersetOrder,
                    targetRepMin: routineExercise.targetRepMin,
                    targetRepMax: routineExercise.targetRepMax,
                    exerciseId: routineExercise.exercise?.id,
                    exerciseSeedKey: routineExercise.exercise.flatMap {
                        $0.seedKey.isEmpty ? nil : $0.seedKey
                    },
                    loadBehaviorRaw: routineExercise.exercise?.loadBehavior.rawValue ?? ExerciseLoadBehavior.resistance.rawValue,
                    alternatives: routineExercise.alternativesList.compactMap { alternative in
                        guard let exercise = alternative.exercise else { return nil }
                        return WatchExerciseAlternative(
                            id: alternative.id,
                            exerciseId: exercise.id,
                            name: exercise.name,
                            muscleGroup: exercise.primaryMuscleGroup,
                            sets: alternative.setsList.map { set in
                                WatchSet(
                                    id: set.id,
                                    reps: set.reps,
                                    weight: set.weight,
                                    restTime: set.restTime
                                )
                            },
                            order: alternative.order,
                            loadBehaviorRaw: exercise.loadBehavior.rawValue,
                            targetRepMin: alternative.targetRepMin,
                            targetRepMax: alternative.targetRepMax
                        )
                    }
                )
            }
        )
    }
}
