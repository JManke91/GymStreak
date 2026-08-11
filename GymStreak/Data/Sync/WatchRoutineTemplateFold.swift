//
//  WatchRoutineTemplateFold.swift
//  GymStreak
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
        // Targets already resolved by a progressive-overload transaction
        // (ticket 04). Their template values were committed by that separate
        // transaction from the TEMPLATE scheme; replaying this workout's
        // performed values over them would regress the overload, so they are
        // excluded from generic set-value writeback here exactly as they are in
        // the authoritative iOS merge. Structural intent is unaffected, and so
        // is an adjusted rest time — the overload transaction commits reps and
        // weight only, so there is no rest value of its own to regress.
        let overloadResolvedIDs = Set(workout.overloadAppliedExerciseIDs ?? [])

        // Delete explicit removals (already-absent IDs are no-ops); fold set
        // values and rest time into every retained slot.
        var exercises = routine.exercises.compactMap { exercise -> WatchExercise? in
            guard !removedIDs.contains(exercise.id) else { return nil }
            guard let completed = workout.exercises.first(where: { $0.id == exercise.id }) else {
                return exercise
            }
            return foldingSets(
                into: exercise,
                from: completed,
                writesSetValues: !overloadResolvedIDs.contains(exercise.id)
            )
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

    // MARK: - Progressive overload (template-only kind, ticket 04)

    /// Folds a pending progressive-overload transaction over a routine — the
    /// same optimistic-overlay contract as the completed-workout kind.
    ///
    /// Targets are resolved by stable ID only (slot, then the alternative's own
    /// scheme when `alternativeID` is set), never by display name, so an
    /// alternative's values can never land in the primary scheme. Application is
    /// idempotent and value-absolute: a set already at the proposed values stays
    /// unchanged, and a set the authoritative base has since moved to a third
    /// value is left alone — iOS is the authority that resolves that conflict,
    /// and its authoritative context retires this overlay either way.
    static func apply(_ intent: WatchProgressiveOverloadIntent, to routine: WatchRoutine) -> WatchRoutine {
        guard intent.isWellFormed else { return routine }
        let changes = Dictionary(uniqueKeysWithValues: intent.setChanges.map { ($0.setID, $0) })

        let exercises = routine.exercises.map { exercise -> WatchExercise in
            guard exercise.id == intent.routineExerciseID else { return exercise }

            guard let alternativeID = intent.alternativeID else {
                return rebuilt(exercise, sets: overloaded(exercise.sets, with: changes),
                               order: exercise.order, supersetId: exercise.supersetId,
                               supersetOrder: exercise.supersetOrder,
                               alternatives: exercise.alternatives)
            }

            let alternatives = exercise.alternatives?.map { alternative -> WatchExerciseAlternative in
                guard alternative.id == alternativeID else { return alternative }
                return WatchExerciseAlternative(
                    id: alternative.id,
                    exerciseId: alternative.exerciseId,
                    name: alternative.name,
                    muscleGroup: alternative.muscleGroup,
                    sets: overloaded(alternative.sets, with: changes),
                    order: alternative.order,
                    loadBehaviorRaw: alternative.loadBehaviorRaw,
                    targetRepMin: alternative.targetRepMin,
                    targetRepMax: alternative.targetRepMax
                )
            }
            return rebuilt(exercise, sets: exercise.sets, order: exercise.order,
                           supersetId: exercise.supersetId, supersetOrder: exercise.supersetOrder,
                           alternatives: alternatives)
        }
        return WatchRoutine(id: routine.id, name: routine.name, exercises: exercises)
    }

    private static func overloaded(
        _ sets: [WatchSet],
        with changes: [UUID: WatchTemplateSetChange]
    ) -> [WatchSet] {
        sets.map { set in
            guard let change = changes[set.id] else { return set }
            // Already at the proposed values (duplicate fold / re-entry), or
            // moved to an unrelated third value by a newer authoritative base.
            let matchesExpected = set.reps == change.expectedReps
                && WatchTemplateSetChange.weightsMatch(set.weight, change.expectedWeight)
            let matchesProposed = set.reps == change.proposedReps
                && WatchTemplateSetChange.weightsMatch(set.weight, change.proposedWeight)
            guard matchesExpected || matchesProposed else { return set }
            return WatchSet(
                id: set.id,
                reps: change.proposedReps,
                weight: change.proposedWeight,
                restTime: set.restTime
            )
        }
    }

    // MARK: - Set fold (retained slots)

    private static func foldingSets(
        into exercise: WatchExercise,
        from completed: CompletedWatchExercise,
        writesSetValues: Bool
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
                    sets: folded(alternative.sets, with: completed.sets, writesValues: writesSetValues),
                    order: alternative.order,
                    loadBehaviorRaw: alternative.loadBehaviorRaw,
                    targetRepMin: alternative.targetRepMin,
                    targetRepMax: alternative.targetRepMax
                )
            }
        } else {
            updatedSets = folded(exercise.sets, with: completed.sets, writesValues: writesSetValues)
        }

        return rebuilt(exercise, sets: updatedSets, order: exercise.order,
                       supersetId: exercise.supersetId, supersetOrder: exercise.supersetOrder,
                       alternatives: updatedAlternatives)
    }

    private static func folded(
        _ sets: [WatchSet],
        with completedSets: [CompletedWatchSet],
        writesValues: Bool
    ) -> [WatchSet] {
        let adjustedRest = adjustedRestTime(of: completedSets)
        return sets.map { set in
            let completed = completedSets.first(where: { $0.id == set.id })
            let writesThisSet = writesValues && completed.map {
                $0.actualReps != $0.plannedReps || $0.actualWeight != $0.plannedWeight
            } == true
            let restTime = adjustedRest ?? set.restTime
            guard writesThisSet || restTime != set.restTime else { return set }
            return WatchSet(
                id: set.id,
                reps: writesThisSet ? (completed?.actualReps ?? set.reps) : set.reps,
                weight: writesThisSet ? (completed?.actualWeight ?? set.weight) : set.weight,
                restTime: restTime
            )
        }
    }

    /// The rest duration the watch explicitly changed during the workout, or nil
    /// when it carries no rest intent. Mirrors the authoritative iOS merge
    /// (`WatchTemplateTransactionService+Validation`): intent is
    /// `restTime != plannedRestTime`, and the value applies to the exercise's
    /// whole scheme because rest is one value per exercise, never per set.
    private static func adjustedRestTime(of completedSets: [CompletedWatchSet]) -> TimeInterval? {
        guard completedSets.contains(where: \.wasRestAdjusted) else { return nil }
        return completedSets.min(by: { $0.order < $1.order })?.restTime
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
