//
//  RoutineTemplateSyncService.swift
//  GymStreak
//
//  Pushes a session's performed values back onto its routine template — the
//  "Update routine" toggle on the save screen, and the same toggle when a past
//  workout is edited.
//
//  Extracted from `WorkoutViewModel` (audit P1.5). The block had grown past
//  "ViewModel → repository call" into real multi-step orchestration: slot
//  matching with a legacy fallback, membership reconciliation, set-count
//  reconciliation, the swapped-alternative branch and the
//  progressive-overload exclusion. None of it is view state, and none of it
//  needs a `WorkoutViewModel`.
//
//  Like `SupersetOrderingService` this mutates the passed `@Model` objects and
//  **never saves**: the caller owns the single save that commits the template
//  write together with whatever else it changed in the same context. It does
//  insert and delete through the repositories, because SwiftData requires a
//  synthesized child to be registered with a context before it can be linked,
//  and removing an object from a relationship array does not delete its record.
//

import Foundation

@MainActor
final class RoutineTemplateSyncService {
    private let routineRepository: RoutineRepository
    private let exerciseRepository: ExerciseRepository

    init(
        routineRepository: RoutineRepository,
        exerciseRepository: ExerciseRepository
    ) {
        self.routineRepository = routineRepository
        self.exerciseRepository = exerciseRepository
    }

    /// Pushes a session's performed values back onto its routine template.
    ///
    /// - Parameter reconcileExerciseMembership: active-workout completion also
    ///   adds/removes template slots to match what was actually performed;
    ///   historical edits deliberately do not, because a routine may have
    ///   changed since that older workout was recorded.
    ///
    /// Does nothing for a session with no routine. Never saves — the caller does.
    func applyPerformedValues(
        from session: WorkoutSession,
        reconcileExerciseMembership: Bool
    ) {
        guard let routine = session.routine else { return }

        let routineExercises = routine.routineExercisesList.sorted { $0.order < $1.order }
        let workoutExercises = session.workoutExercisesList.sorted { $0.order < $1.order }
        let allowsLegacyFallback = !reconcileExerciseMembership
            && workoutExercises.allSatisfy { $0.routineExerciseId == nil }
        var claimedRoutineExerciseIds: Set<UUID> = []
        let matches: [(workout: WorkoutExercise, routine: RoutineExercise?)] = workoutExercises.map {
            workoutExercise in
            let match = matchingRoutineExercise(
                for: workoutExercise,
                in: routineExercises,
                excluding: claimedRoutineExerciseIds,
                allowsLegacyFallback: allowsLegacyFallback
            )
            if let match {
                claimedRoutineExerciseIds.insert(match.id)
            }
            return (workoutExercise, match)
        }

        if reconcileExerciseMembership {
            for removedExercise in routineExercises where !claimedRoutineExerciseIds.contains(removedExercise.id) {
                routine.routineExercises?.removeAll { $0.id == removedExercise.id }
                for set in removedExercise.setsList {
                    removedExercise.sets?.removeAll { $0.id == set.id }
                    routineRepository.delete(set)
                }
                routineRepository.delete(removedExercise)
            }

            for (order, routineExercise) in routine.routineExercisesList
                .sorted(by: { $0.order < $1.order })
                .enumerated() {
                routineExercise.order = order
            }
        }

        for match in matches {
            guard let routineExercise = match.routine else {
                if reconcileExerciseMembership {
                    appendRoutineExercise(from: match.workout, to: routine)
                }
                continue
            }

            // Swapped exercises write their values back into the performed
            // alternative's own set scheme — the primary's sets stay untouched.
            if match.workout.wasSwapped {
                if let alternative = routineExercise.alternativesList.first(where: { $0.exercise?.id == match.workout.exerciseId }) {
                    updateAlternativeTemplateSets(alternative, from: match.workout)
                }
                continue
            }

            updatePrimaryTemplateSets(routineExercise, from: match.workout)
        }

        routine.updatedAt = Date()
    }

    private func matchingRoutineExercise(
        for workoutExercise: WorkoutExercise,
        in candidates: [RoutineExercise],
        excluding claimedIds: Set<UUID>,
        allowsLegacyFallback: Bool
    ) -> RoutineExercise? {
        if let slotId = workoutExercise.routineExerciseId {
            return candidates.first { $0.id == slotId && !claimedIds.contains($0.id) }
        }

        guard allowsLegacyFallback else { return nil }
        let originId = workoutExercise.plannedExerciseId ?? workoutExercise.exerciseId
        let originName = workoutExercise.plannedExerciseName ?? workoutExercise.exerciseName
        return candidates.first { candidate in
            guard !claimedIds.contains(candidate.id) else { return false }
            if let originId, let candidateId = candidate.exercise?.id {
                return candidateId == originId
            }
            return candidate.exercise?.name == originName
        }
    }

    private func appendRoutineExercise(from workoutExercise: WorkoutExercise, to routine: Routine) {
        guard let exerciseId = workoutExercise.exerciseId,
              let exercise = exerciseRepository.fetch(id: exerciseId) else { return }

        let routineExercise = RoutineExercise(order: routine.routineExercisesList.count)
        routineRepository.insert(routineExercise)
        routineExercise.exercise = exercise
        routineExercise.routine = routine
        if !routine.routineExercisesList.contains(where: { $0.id == routineExercise.id }) {
            routine.routineExercises?.append(routineExercise)
        }

        for (order, workoutSet) in workoutExercise.setsList
            .sorted(by: { $0.order < $1.order })
            .enumerated() {
            let routineSet = ExerciseSet(
                reps: workoutSet.actualReps,
                weight: workoutSet.actualWeight,
                restTime: workoutSet.restTime,
                order: order
            )
            routineRepository.insert(routineSet)
            routineSet.routineExercise = routineExercise
            if !routineExercise.setsList.contains(where: { $0.id == routineSet.id }) {
                routineExercise.sets?.append(routineSet)
            }
        }

        workoutExercise.routineExerciseId = routineExercise.id
    }

    /// An exercise whose progressive-overload apply owns the template scheme is
    /// excluded from generic set-value writeback: its performed values are by
    /// definition the weights from BEFORE the increase, so writing them back at
    /// Save would silently undo the increase and immediately re-qualify the
    /// exercise. (Until the increase stopped rewriting the live sets this was
    /// harmless only by accident — the performed values had been overwritten
    /// with the overload target.) Both Watch paths already apply this rule via
    /// `overloadAppliedExerciseIDs` — `WatchRoutineTemplateFold` and
    /// `WatchTemplateTransactionService+Validation`. Set count, order and rest
    /// time still reconcile; a set ADDED during such a workout still seeds its
    /// new template set from the performance, since it has no counterpart the
    /// increase could have raised.
    private func updatePrimaryTemplateSets(
        _ routineExercise: RoutineExercise,
        from workoutExercise: WorkoutExercise
    ) {
        let exerciseRestTime = workoutExercise.setsList.first?.restTime ?? 60.0
        let workoutSets = workoutExercise.setsList.sorted(by: { $0.order < $1.order })
        var routineSets = routineExercise.setsList.sorted(by: { $0.order < $1.order })
        let writesSetValues = !workoutExercise.progressiveOverloadApplied

        if routineSets.count > workoutSets.count {
            for routineSet in routineSets[workoutSets.count...] {
                routineExercise.sets?.removeAll { $0.id == routineSet.id }
                routineRepository.delete(routineSet)
            }
            routineSets = Array(routineSets[..<workoutSets.count])
        }

        for (index, routineSet) in routineSets.enumerated() {
            routineSet.order = index
            routineSet.restTime = exerciseRestTime
            let workoutSet = workoutSets[index]
            if workoutSet.isCompleted && writesSetValues {
                routineSet.reps = workoutSet.actualReps
                routineSet.weight = workoutSet.actualWeight
            }
        }

        if workoutSets.count > routineSets.count {
            // A set added during the workout has no template counterpart the
            // increase could have raised, so for an overload-applied exercise
            // it inherits the raised scheme (last template set) instead of the
            // pre-increase performance — otherwise the template ends up mixing
            // raised and unraised sets.
            let raised = writesSetValues ? nil : routineSets.last
            for index in routineSets.count..<workoutSets.count {
                let workoutSet = workoutSets[index]
                let newRoutineSet = ExerciseSet(
                    reps: raised?.reps ?? workoutSet.actualReps,
                    weight: raised?.weight ?? workoutSet.actualWeight,
                    restTime: exerciseRestTime,
                    order: index
                )
                routineRepository.insert(newRoutineSet)
                newRoutineSet.routineExercise = routineExercise
                if !routineExercise.setsList.contains(where: { $0.id == newRoutineSet.id }) {
                    routineExercise.sets?.append(newRoutineSet)
                }
            }
        }
    }

    /// Mirrors the primary-set template update for a performed alternative:
    /// reps/weight from completed sets, rest time from the exercise, and the
    /// alternative's set count reconciled to the session's. The same
    /// overload-applied exclusion as `updatePrimaryTemplateSets` applies.
    private func updateAlternativeTemplateSets(_ alternative: RoutineExerciseAlternative, from workoutExercise: WorkoutExercise) {
        let exerciseRestTime = workoutExercise.setsList.first?.restTime ?? 60.0
        let workoutSets = workoutExercise.setsList.sorted(by: { $0.order < $1.order })
        var alternativeSets = alternative.setsList
        let writesSetValues = !workoutExercise.progressiveOverloadApplied

        // Remove surplus template sets beyond the session's set count
        if alternativeSets.count > workoutSets.count {
            for alternativeSet in alternativeSets[workoutSets.count...] {
                alternative.sets?.removeAll { $0.id == alternativeSet.id }
                routineRepository.delete(alternativeSet)
            }
            alternativeSets = Array(alternativeSets[..<workoutSets.count])
        }

        // Update existing template sets in order
        for (index, alternativeSet) in alternativeSets.enumerated() {
            alternativeSet.order = index
            alternativeSet.restTime = exerciseRestTime
            let workoutSet = workoutSets[index]
            if workoutSet.isCompleted && writesSetValues {
                alternativeSet.reps = workoutSet.actualReps
                alternativeSet.weight = workoutSet.actualWeight
            }
        }

        // Append new template sets for extra session sets. Same rule as the
        // primary path: an overload-applied exercise seeds them from the raised
        // scheme, not from the pre-increase performance.
        if workoutSets.count > alternativeSets.count {
            let raised = writesSetValues ? nil : alternativeSets.last
            for index in alternativeSets.count..<workoutSets.count {
                let workoutSet = workoutSets[index]
                let newSet = AlternativeExerciseSet(
                    reps: raised?.reps ?? workoutSet.actualReps,
                    weight: raised?.weight ?? workoutSet.actualWeight,
                    restTime: exerciseRestTime,
                    order: index
                )
                newSet.alternative = alternative
                if alternative.sets == nil { alternative.sets = [] }
                alternative.sets?.append(newSet)
            }
        }
    }
}
