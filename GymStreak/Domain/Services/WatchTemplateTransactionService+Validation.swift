//
//  WatchTemplateTransactionService+Validation.swift
//  GymStreak
//
//  Validation half of a watch template transaction (ticket 07): resolves the
//  whole request — set-only intent, structural membership intent, and library
//  identities — into a `MergePlan` BEFORE any mutation, so a malformed payload
//  or an unresolvable added exercise rejects the entire request atomically. See
//  `WatchTemplateTransactionService.swift` for the transaction contract.
//

import Foundation

extension WatchTemplateTransactionService {
    enum Validation {
        case success(MergePlan)
        case failure(String)
    }

    /// Validates set-only intent PLUS structural add/remove intent against the
    /// current routine, resolving every mutation before any is applied.
    func validateMerge(_ workout: IncomingWatchWorkout, against routine: Routine?) -> Validation {
        guard let routine else {
            return .failure("routine \(workout.routineId) not found")
        }

        // Structural wire invariants (defensive; the watch produces valid
        // intent by construction). A malformed payload is terminally rejected,
        // never repaired or guessed at.
        if let reason = validateMembershipIntent(workout) {
            return .failure(reason)
        }

        // Resolve every addition's library exercise up front (UUID, then
        // non-empty seed key — never by name, never resurrecting a deleted
        // exercise). An unresolvable addition rejects the whole request.
        var additions: [Addition] = []
        for addedID in workout.addedRoutineExerciseIDs {
            guard let completed = workout.exercises.first(where: { $0.id == addedID }) else {
                return .failure("added slot \(addedID) missing from final exercises")
            }
            guard let exercise = resolveLibraryExercise(completed) else {
                return .failure("added exercise '\(completed.name)' could not be resolved in the library")
            }
            additions.append(Addition(completed: completed, exercise: exercise))
        }

        // Resolve removals against the CURRENT routine; an already-absent slot
        // (deleted concurrently on iOS) is a no-op, never an error.
        let removals = workout.removedRoutineExerciseIDs.compactMap { id in
            routine.routineExercisesList.first { $0.id == id }
        }

        // Value + rest reconcile for retained (non-added) slots.
        //
        // Targets already resolved by a progressive-overload transaction
        // (ticket 04) are excluded from the VALUE writeback. That transaction
        // committed template values derived from the TEMPLATE scheme; this
        // workout's performed values are a different thing, and writing them
        // here would silently replace the next-workout target the user
        // explicitly chose. The product rule is that once overload is applied
        // for a target during a workout, later edits to those performed sets
        // stay history-only. Structural intent for the same slot is unaffected,
        // and so is an adjusted rest time (see below).
        let addedIDs = Set(workout.addedRoutineExerciseIDs)
        let overloadResolvedIDs = Set(workout.overloadAppliedExerciseIDs)
        var updates: [SetUpdate] = []
        for completedExercise in workout.exercises where !addedIDs.contains(completedExercise.id) {
            // Rest reconciles even for an overload-resolved exercise: the
            // progressive-overload transaction commits reps and weight, never
            // the rest time, so there is nothing here it could regress. iOS's
            // own `RoutineTemplateSyncService.updatePrimaryTemplateSets` writes rest
            // outside its overload exclusion for exactly this reason.
            let modifiedSets = overloadResolvedIDs.contains(completedExercise.id)
                ? []
                : completedExercise.sets.filter {
                    $0.actualReps != $0.plannedReps || $0.actualWeight != $0.plannedWeight
                }
            let adjustedRestTime = adjustedRestTime(of: completedExercise)
            if let adjustedRestTime {
                // The slot goes to the sink as a UUID; the Data layer shortens
                // it into the same one-way token the watch and ingest lines use,
                // so all three correlate on slot identity.
                let slot = routine.routineExercisesList.first { $0.id == completedExercise.id }
                // Measured against the scheme the write will actually hit: a
                // swapped exercise writes into its ALTERNATIVE's sets, so
                // reporting the primary's would answer the wrong question in
                // precisely the case worth asking about.
                let isSwapped = completedExercise.plannedExerciseId != nil
                let targetRests = isSwapped
                    ? slot?.alternativesList
                        .first { $0.exercise?.id == completedExercise.exerciseId }?
                        .setsList.map(\.restTime)
                    : slot?.setsList.map(\.restTime)
                diagnostics?(
                    completedExercise.id,
                    "rest intent \(Int(adjustedRestTime))"
                    + " slotFound=\(slot != nil)"
                    + " alreadyAtValue=\(targetRests.map { !$0.isEmpty && $0.allSatisfy { $0 == adjustedRestTime } } ?? false)"
                    + " swapped=\(isSwapped)"
                )
            }
            guard !modifiedSets.isEmpty || adjustedRestTime != nil else { continue }

            guard let routineExercise = routine.routineExercisesList
                .first(where: { $0.id == completedExercise.id }) else {
                // A retained slot the watch edited but iOS deleted concurrently:
                // the deletion wins. This is a no-op, never an implicit re-add.
                continue
            }

            // A swapped exercise's completed sets carry the alternative's own
            // set ids (the watch rebuilds the scheme from the alternative on
            // swap), so those values belong to that alternative's template —
            // matching them against the primary's sets can never succeed.
            if completedExercise.plannedExerciseId != nil {
                guard let alternative = routineExercise.alternativesList
                    .first(where: { $0.exercise?.id == completedExercise.exerciseId }) else {
                    // An alternative iOS deleted concurrently: with nothing to
                    // write this stays the pre-existing no-op, and a real value
                    // intent still rejects the whole request.
                    if modifiedSets.isEmpty { continue }
                    return .failure("alternative \(completedExercise.name) not found on \(completedExercise.id)")
                }
                var restTargets = restTargetIDs(alternative.setsList, adjustedTo: adjustedRestTime)
                for completedSet in modifiedSets {
                    guard let set = alternative.setsList.first(where: { $0.id == completedSet.id }) else {
                        return .failure("alternative set \(completedSet.id) not found")
                    }
                    updates.append(SetUpdate(
                        target: .alternativeSet(set),
                        reps: completedSet.actualReps,
                        weight: completedSet.actualWeight,
                        restTime: restTargets.remove(set.id) != nil ? adjustedRestTime : nil
                    ))
                }
                updates.append(contentsOf: alternative.setsList
                    .filter { restTargets.contains($0.id) }
                    .map { SetUpdate(target: .alternativeSet($0), reps: nil, weight: nil, restTime: adjustedRestTime) })
                continue
            }

            var restTargets = restTargetIDs(routineExercise.setsList, adjustedTo: adjustedRestTime)
            for completedSet in modifiedSets {
                guard let set = routineExercise.setsList.first(where: { $0.id == completedSet.id }) else {
                    return .failure("set \(completedSet.id) not found")
                }
                updates.append(SetUpdate(
                    target: .routineSet(set),
                    reps: completedSet.actualReps,
                    weight: completedSet.actualWeight,
                    restTime: restTargets.remove(set.id) != nil ? adjustedRestTime : nil
                ))
            }
            updates.append(contentsOf: routineExercise.setsList
                .filter { restTargets.contains($0.id) }
                .map { SetUpdate(target: .routineSet($0), reps: nil, weight: nil, restTime: adjustedRestTime) })
        }
        return .success(MergePlan(setUpdates: updates, removals: removals, additions: additions))
    }

    /// The rest duration the watch explicitly changed during this workout, or
    /// nil when it carries no rest intent (untouched rest, or a payload from a
    /// watch build that predates the rest baseline).
    ///
    /// Intent is `restTime != plannedRestTime`, the same planned-vs-actual test
    /// the set values use — never a diff against the live template, which would
    /// mistake a concurrent iPhone rest edit for watch intent and revert it.
    /// The value is the exercise's first performed set's rest: rest is one value
    /// per exercise everywhere in the app, so the whole scheme takes it (this is
    /// what `RoutineTemplateSyncService.updatePrimaryTemplateSets` does for an iPhone
    /// workout).
    func adjustedRestTime(of exercise: IncomingWatchExercise) -> TimeInterval? {
        guard exercise.sets.contains(where: \.wasRestAdjusted) else { return nil }
        return exercise.sets.min(by: { $0.order < $1.order })?.restTime
    }

    /// The template sets that would actually change if `restTime` were written,
    /// so an unchanged set is never touched and re-applying is a no-op.
    private func restTargetIDs<Row: TemplateSetRow>(
        _ sets: [Row],
        adjustedTo restTime: TimeInterval?
    ) -> Set<UUID> {
        guard let restTime else { return [] }
        return Set(sets.filter { $0.restTime != restTime }.map(\.id))
    }

    /// Structural wire invariants. Returns a rejection reason, or nil when the
    /// membership intent is internally consistent.
    private func validateMembershipIntent(_ workout: IncomingWatchWorkout) -> String? {
        let finalIDs = workout.exercises.map(\.id)
        guard Set(finalIDs).count == finalIDs.count else { return "duplicate final slot IDs" }
        let setIDs = workout.exercises.flatMap { $0.sets.map(\.id) }
        guard Set(setIDs).count == setIDs.count else { return "duplicate set IDs in payload" }

        let added = workout.addedRoutineExerciseIDs
        let removed = workout.removedRoutineExerciseIDs
        guard Set(added).count == added.count else { return "duplicate added slot IDs" }
        guard Set(removed).count == removed.count else { return "duplicate removed slot IDs" }
        guard Set(added).isDisjoint(with: Set(removed)) else { return "added and removed slot IDs overlap" }

        let finalIDSet = Set(finalIDs)
        guard added.allSatisfy({ finalIDSet.contains($0) }) else {
            return "added slot ID absent from final exercises"
        }
        guard removed.allSatisfy({ !finalIDSet.contains($0) }) else {
            return "removed slot ID present in final exercises"
        }
        return nil
    }

    /// Resolves a Watch-added exercise to a library `Exercise`: by payload UUID
    /// first, then by the deterministic seed-key survivor (oldest `createdAt`,
    /// then smallest `id`) matching `DefaultContentSeeder`. Never falls back by
    /// name and never recreates/reinserts an exercise.
    private func resolveLibraryExercise(_ completed: IncomingWatchExercise) -> Exercise? {
        if let id = completed.exerciseId, let exercise = exerciseRepository.fetch(id: id) {
            return exercise
        }
        guard let seedKey = completed.exerciseSeedKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !seedKey.isEmpty else { return nil }
        return exerciseRepository.fetchBySeedKey(seedKey)
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .first
    }
}
