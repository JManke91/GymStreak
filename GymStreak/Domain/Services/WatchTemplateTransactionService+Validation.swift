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

        // Set-only reconcile for retained (non-added) slots.
        let addedIDs = Set(workout.addedRoutineExerciseIDs)
        var updates: [SetUpdate] = []
        for completedExercise in workout.exercises where !addedIDs.contains(completedExercise.id) {
            let modifiedSets = completedExercise.sets.filter {
                $0.actualReps != $0.plannedReps || $0.actualWeight != $0.plannedWeight
            }
            guard !modifiedSets.isEmpty else { continue }

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
                    return .failure("alternative \(completedExercise.name) not found on \(completedExercise.id)")
                }
                for completedSet in modifiedSets {
                    guard let set = alternative.setsList.first(where: { $0.id == completedSet.id }) else {
                        return .failure("alternative set \(completedSet.id) not found")
                    }
                    updates.append(SetUpdate(
                        target: .alternativeSet(set),
                        reps: completedSet.actualReps,
                        weight: completedSet.actualWeight
                    ))
                }
                continue
            }

            for completedSet in modifiedSets {
                guard let set = routineExercise.setsList.first(where: { $0.id == completedSet.id }) else {
                    return .failure("set \(completedSet.id) not found")
                }
                updates.append(SetUpdate(
                    target: .routineSet(set),
                    reps: completedSet.actualReps,
                    weight: completedSet.actualWeight
                ))
            }
        }
        return .success(MergePlan(setUpdates: updates, removals: removals, additions: additions))
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
