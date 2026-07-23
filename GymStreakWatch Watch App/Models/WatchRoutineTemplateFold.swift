//
//  WatchRoutineTemplateFold.swift
//  GymStreakWatch Watch App
//
//  The watch's optimistic template overlay (set-value fold + ticket-07
//  structural add/remove), split out of WatchRoutineSyncModels.swift to keep
//  both files within the repository's file-length convention.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Models/` — keep them in sync. There is no watch
//  unit-test target; the iOS test target covers this logic through its copy.
//

import Foundation

/// Folds a pending template transaction's intent over a routine — the watch's
/// optimistic overlay (ticket 05, extended for structural add/remove in
/// ticket 07).
///
/// Set-only intent mirrors iOS ingestion: only sets whose actual values differ
/// from planned are applied, and a swapped exercise's values belong to the
/// matching alternative's scheme, never the primary's.
///
/// Structural intent (`addedRoutineExerciseIDs` / `removedRoutineExerciseIDs`)
/// deletes explicitly-removed slots with the same superset cleanup iOS
/// performs, appends explicit additions with their Watch-minted slot UUID and
/// pending provenance, preserves unrelated slots, normalizes order, and is
/// idempotent under duplicate finalization/transport (an addition already
/// present is never appended twice). When there is no structural intent the
/// set-only behavior is byte-for-byte unchanged.
enum WatchRoutineTemplateFold {
    static func apply(_ workout: CompletedWatchWorkout, to routine: WatchRoutine) -> WatchRoutine {
        guard workout.routineId == routine.id, workout.shouldUpdateTemplate else { return routine }

        let removedIDs = Set(workout.removedRoutineExerciseIDs ?? [])
        let addedIDs = workout.addedRoutineExerciseIDs ?? []

        // Delete explicit removals (already-absent IDs are no-ops); fold set
        // values into every retained slot.
        var exercises = routine.exercises.compactMap { exercise -> WatchExercise? in
            guard !removedIDs.contains(exercise.id) else { return nil }
            guard let completed = workout.exercises.first(where: { $0.id == exercise.id }) else {
                return exercise
            }
            return foldingSets(into: exercise, from: completed)
        }

        // No structural intent → preserve the exact set-only overlay (order and
        // every other field untouched).
        guard !removedIDs.isEmpty || !addedIDs.isEmpty else {
            return WatchRoutine(id: routine.id, name: routine.name, exercises: exercises)
        }

        // Superset cleanup for any group that lost a member to a removal: two or
        // more remaining members keep the group UUID and renumber contiguously;
        // a lone survivor is cleared.
        let affectedGroups = Set(
            routine.exercises.filter { removedIDs.contains($0.id) }.compactMap(\.supersetId)
        )
        for group in affectedGroups {
            exercises = cleaningUpSuperset(group, in: exercises)
        }

        // Append explicit additions whose minted slot UUID is still absent
        // (idempotent under retransmission / duplicate delivery).
        let presentIDs = Set(exercises.map(\.id))
        for addedID in addedIDs where !presentIDs.contains(addedID) {
            guard let completed = workout.exercises.first(where: { $0.id == addedID }) else { continue }
            exercises.append(addedSlot(from: completed))
        }

        // Normalize order contiguously so the overlay matches iOS persistence.
        exercises = exercises.enumerated().map { index, exercise in
            rebuilt(exercise, sets: exercise.sets, order: index,
                    supersetId: exercise.supersetId, supersetOrder: exercise.supersetOrder,
                    alternatives: exercise.alternatives)
        }

        return WatchRoutine(id: routine.id, name: routine.name, exercises: exercises)
    }

    // MARK: - Set fold (retained slots)

    private static func foldingSets(
        into exercise: WatchExercise,
        from completed: CompletedWatchExercise
    ) -> WatchExercise {
        var updatedSets = exercise.sets
        var updatedAlternatives = exercise.alternatives

        if completed.plannedExerciseId != nil {
            updatedAlternatives = exercise.alternatives?.map { alternative in
                guard alternative.exerciseId == completed.exerciseId else { return alternative }
                return WatchExerciseAlternative(
                    id: alternative.id,
                    exerciseId: alternative.exerciseId,
                    name: alternative.name,
                    muscleGroup: alternative.muscleGroup,
                    sets: folded(alternative.sets, with: completed.sets),
                    order: alternative.order,
                    loadBehaviorRaw: alternative.loadBehaviorRaw
                )
            }
        } else {
            updatedSets = folded(exercise.sets, with: completed.sets)
        }

        return rebuilt(exercise, sets: updatedSets, order: exercise.order,
                       supersetId: exercise.supersetId, supersetOrder: exercise.supersetOrder,
                       alternatives: updatedAlternatives)
    }

    private static func folded(_ sets: [WatchSet], with completedSets: [CompletedWatchSet]) -> [WatchSet] {
        sets.map { set in
            guard let completed = completedSets.first(where: { $0.id == set.id }),
                  completed.actualReps != completed.plannedReps
                    || completed.actualWeight != completed.plannedWeight else {
                return set
            }
            return WatchSet(
                id: set.id,
                reps: completed.actualReps,
                weight: completed.actualWeight,
                restTime: set.restTime
            )
        }
    }

    // MARK: - Structural helpers

    /// Materializes an added slot from its completed-workout exercise. Added
    /// slots keep their Watch-minted slot/set UUIDs, copy actual reps/weight/
    /// rest, are standalone (no superset, no alternatives, no rep-range goal),
    /// and are flagged pending until iOS confirms them — so a later workout's
    /// baseline can still cancel an unconfirmed addition.
    private static func addedSlot(from completed: CompletedWatchExercise) -> WatchExercise {
        WatchExercise(
            id: completed.id,
            name: completed.name,
            muscleGroup: completed.muscleGroup,
            sets: completed.sets.sorted { $0.order < $1.order }.map { set in
                WatchSet(id: set.id, reps: set.actualReps, weight: set.actualWeight, restTime: set.restTime)
            },
            order: 0,
            supersetId: nil,
            supersetOrder: 0,
            targetRepMin: nil,
            targetRepMax: nil,
            exerciseId: completed.exerciseId,
            exerciseSeedKey: completed.exerciseSeedKey,
            isPendingWatchAddition: true,
            loadBehaviorRaw: completed.loadBehaviorRaw,
            alternatives: nil
        )
    }

    private static func cleaningUpSuperset(_ group: UUID, in exercises: [WatchExercise]) -> [WatchExercise] {
        let members = exercises.enumerated().filter { $0.element.supersetId == group }
        guard members.count >= 2 else {
            guard let survivor = members.first else { return exercises }
            var result = exercises
            result[survivor.offset] = rebuilt(
                survivor.element, sets: survivor.element.sets, order: survivor.element.order,
                supersetId: nil, supersetOrder: 0, alternatives: survivor.element.alternatives
            )
            return result
        }
        let ordered = members.sorted { $0.element.supersetOrder < $1.element.supersetOrder }
        var result = exercises
        for (newOrder, item) in ordered.enumerated() {
            result[item.offset] = rebuilt(
                item.element, sets: item.element.sets, order: item.element.order,
                supersetId: group, supersetOrder: newOrder, alternatives: item.element.alternatives
            )
        }
        return result
    }

    /// `WatchExercise`'s structural fields are `let`, so any change is a full
    /// rebuild: only the passed fields change, every other field is copied.
    private static func rebuilt(
        _ e: WatchExercise,
        sets: [WatchSet],
        order: Int,
        supersetId: UUID?,
        supersetOrder: Int,
        alternatives: [WatchExerciseAlternative]?
    ) -> WatchExercise {
        WatchExercise(
            id: e.id,
            name: e.name,
            muscleGroup: e.muscleGroup,
            sets: sets,
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder,
            targetRepMin: e.targetRepMin,
            targetRepMax: e.targetRepMax,
            exerciseId: e.exerciseId,
            exerciseSeedKey: e.exerciseSeedKey,
            isPendingWatchAddition: e.isPendingWatchAddition,
            loadBehaviorRaw: e.loadBehaviorRaw,
            alternatives: alternatives
        )
    }
}
