//
//  WatchTemplateTransactionService+Structural.swift
//  GymStreak
//
//  The structural half of a watch template transaction (ticket 07, in-workout
//  routine editing): merging explicit add/remove intent into the CURRENT
//  SwiftData routine, inside the same isolated one-save transaction as the
//  set-only update and denormalized history.
//
//  Everything here runs only after `validateMerge` resolved the whole request,
//  so these methods never fail — they apply an already-validated plan. Only
//  explicit intent is applied: unrelated current iOS slots (including
//  concurrent additions/reorders) are preserved, and the merge is idempotent
//  (already-absent removals are no-ops; a minted addition slot is inserted
//  only when absent; set updates set values). See the header of
//  `WatchTemplateTransactionService.swift` for the transaction contract.
//

import Foundation

extension WatchTemplateTransactionService {
    /// One validated library addition: the completed-workout exercise that
    /// carries the Watch-minted slot/set UUIDs and configured values, plus the
    /// resolved canonical library `Exercise` to link the new slot to.
    struct Addition {
        let completed: IncomingWatchExercise
        let exercise: Exercise
    }

    /// The fully resolved template mutation, produced by `validateMerge` before
    /// anything is applied. `removals` are current routine slots that still
    /// exist; `additions` are in payload order.
    struct MergePlan {
        var setUpdates: [SetUpdate]
        var removals: [RoutineExercise]
        var additions: [Addition]

        static let empty = MergePlan(setUpdates: [], removals: [], additions: [])
    }

    /// Applies the validated structural plan against the current routine.
    /// Mirrors the watch's optimistic fold exactly (remove → superset cleanup →
    /// append → normalize order) so both platforms converge on the same routine.
    func applyStructural(_ plan: MergePlan, to routine: Routine) {
        guard !plan.removals.isEmpty || !plan.additions.isEmpty else { return }

        // 1. Delete explicit removals and their child sets through the
        //    repository (removing from the relationship array alone would not
        //    delete the underlying rows).
        let affectedGroups = Set(plan.removals.compactMap(\.supersetId))
        for removal in plan.removals {
            routine.routineExercises?.removeAll { $0.id == removal.id }
            for set in removal.setsList {
                removal.sets?.removeAll { $0.id == set.id }
                routineRepository.delete(set)
            }
            routineRepository.delete(removal)
        }

        // 2. Dissolve/renumber each superset that lost a member. Read the
        //    CURRENT (post-removal) group — never restore stale group metadata.
        for group in affectedGroups {
            cleanUpSuperset(group, in: routine)
        }

        // 3. Renumber survivors, append additions at the end in payload order,
        //    then normalize once more so the final order is contiguous.
        normalizeOrder(routine)
        for addition in plan.additions {
            appendAddition(addition, to: routine)
        }
        normalizeOrder(routine)
    }

    /// Superset cleanup on the current routine: two or more remaining members
    /// keep the group UUID and renumber contiguously; a lone survivor (or none)
    /// is cleared.
    private func cleanUpSuperset(_ group: UUID, in routine: Routine) {
        let members = routine.routineExercisesList.filter { $0.supersetId == group }
        guard members.count >= 2 else {
            for member in members {
                member.supersetId = nil
                member.supersetOrder = 0
            }
            return
        }
        for (order, member) in members.sorted(by: { $0.supersetOrder < $1.supersetOrder }).enumerated() {
            member.supersetOrder = order
        }
    }

    private func normalizeOrder(_ routine: Routine) {
        for (order, exercise) in routine.routineExercisesList
            .sorted(by: { $0.order < $1.order })
            .enumerated() {
            exercise.order = order
        }
    }

    /// Inserts one validated addition with the Watch-minted slot UUID, links
    /// the canonical library exercise and routine, and creates contiguous
    /// `ExerciseSet` rows with the Watch-minted set UUIDs and copied actual
    /// values. New slots are standalone (no alternatives, no rep-range goal,
    /// outside any superset). Idempotent: a slot whose minted UUID already
    /// exists is never appended twice.
    private func appendAddition(_ addition: Addition, to routine: Routine) {
        let completed = addition.completed
        guard !routine.routineExercisesList.contains(where: { $0.id == completed.id }) else { return }

        // Insert the unattached slot BEFORE wiring relationships (SwiftData
        // requires both sides to share a context before linking).
        let routineExercise = RoutineExercise(order: routine.routineExercisesList.count)
        routineExercise.id = completed.id
        routineRepository.insert(routineExercise)
        routineExercise.exercise = addition.exercise
        routineExercise.routine = routine
        if !routine.routineExercisesList.contains(where: { $0.id == routineExercise.id }) {
            routine.routineExercises?.append(routineExercise)
        }

        for (order, completedSet) in completed.sets.sorted(by: { $0.order < $1.order }).enumerated() {
            let set = ExerciseSet(
                reps: completedSet.actualReps,
                weight: completedSet.actualWeight,
                restTime: completedSet.restTime,
                order: order
            )
            set.id = completedSet.id
            routineRepository.insert(set)
            set.routineExercise = routineExercise
            if !routineExercise.setsList.contains(where: { $0.id == set.id }) {
                routineExercise.sets?.append(set)
            }
        }
    }
}
