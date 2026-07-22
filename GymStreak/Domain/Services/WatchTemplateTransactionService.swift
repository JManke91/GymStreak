//
//  WatchTemplateTransactionService.swift
//  GymStreak
//
//  Executes one watch template transaction as an all-or-nothing local
//  transaction (ticket 05, in-workout routine editing).
//
//  The generic seam: a transaction may or may not carry history. This ticket
//  implements the completed-workout kind (history + set-only template intent);
//  `executeTemplateOnly` is the same phase sequence without any history, so a
//  later template-only kind (e.g. progressive overload) reuses this executor
//  rather than growing a second protocol. It must never fabricate history just
//  because a transaction has no workout.
//
//  Ordering, receipts, acknowledgment, and authoritative-context staging are
//  the coordinator's job — this service only validates, stages, and commits
//  exactly once through the injected (isolated) repositories.
//

import Foundation

@MainActor
final class WatchTemplateTransactionService {
    /// Terminal decision plus the failure case that is NOT terminal.
    enum Outcome {
        /// The complete requested transaction committed.
        case applied
        /// A deliberate terminal decision: history (if any) was saved, the
        /// routine is byte-for-byte untouched. Acknowledged as `rejected`.
        case rejected(String)
        /// The SwiftData save failed. Nothing is acknowledged and both durable
        /// queues are retained; the isolated context is rolled back by the
        /// caller.
        case saveFailed(Error)
    }

    private let routineRepository: RoutineRepository
    private let workoutSessionRepository: WorkoutSessionRepository
    private let historyService: WatchWorkoutIngestionService

    init(routineRepository: RoutineRepository, workoutSessionRepository: WorkoutSessionRepository) {
        self.routineRepository = routineRepository
        self.workoutSessionRepository = workoutSessionRepository
        self.historyService = WatchWorkoutIngestionService(
            routineRepository: routineRepository,
            workoutSessionRepository: workoutSessionRepository
        )
    }

    /// Completed-workout kind: denormalized history and the complete set-only
    /// template update stage in the same isolated context and commit in ONE
    /// save. Validation runs before any mutation, so a missing routine or a
    /// missing/unmatched required row rejects the whole request instead of
    /// applying part of it.
    func execute(_ workout: IncomingWatchWorkout) -> Outcome {
        let routine = liveRoutine(for: workout)

        // Validate the complete request first — no partial updates.
        let plan: [SetUpdate]
        var rejection: String?
        switch validate(workout, against: routine) {
        case .failure(let reason):
            plan = []
            rejection = reason
        case .success(let updates):
            plan = updates
        }

        // History is staged either way: a rejection is a terminal decision
        // about the template, never a reason to lose the recorded workout.
        let session: WorkoutSession
        switch historyService.stageHistory(workout) {
        case .duplicate(let existing):
            // Trust only the witness written by this atomic transaction path.
            // Legacy builds set didUpdateTemplate before a separate template
            // save, so that flag alone cannot prove the template committed.
            if let transactionID = workout.templateTransactionID,
               existing.watchTemplateTransactionID == transactionID,
               let raw = existing.watchTemplateOutcomeRaw,
               let outcome = TemplateTransactionOutcome(rawValue: raw) {
                // The commit happened and only its receipt was lost. Never
                // reapply old values over a newer user edit.
                switch outcome {
                case .applied: return .applied
                case .rejected:
                    return .rejected("previous atomic attempt rejected template intent")
                }
            }
            // Legacy history without an atomic witness still needs the
            // idempotent upgrade reconciliation required by the protocol.
            session = existing
        case .staged(let staged):
            session = staged
        }

        if rejection == nil {
            apply(plan)
            session.didUpdateTemplate = true
            markAtomicOutcome(.applied, transactionID: workout.templateTransactionID, on: session)
        } else {
            session.didUpdateTemplate = false
            markAtomicOutcome(.rejected, transactionID: workout.templateTransactionID, on: session)
        }

        // One save for both halves. On a rejection the routine was never
        // mutated, so it is not touched by the commit either.
        if let failure = commit(routine: rejection == nil ? routine : nil) { return failure }
        NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)

        if let rejection {
            print("Template transaction rejected: \(rejection) — history saved, routine untouched")
            return .rejected(rejection)
        }
        print("Template transaction applied: \(plan.count) set(s) on '\(workout.routineName)'")
        return .applied
    }

    /// Template-only kind (no history): validate and stage only the routine
    /// mutation, then commit once. Reserved for later template-only
    /// transaction kinds; it deliberately shares this executor's phases.
    func executeTemplateOnly(routineID: UUID, updates: [SetUpdate]) -> Outcome {
        guard let routine = routineRepository.fetch(id: routineID) else {
            if let failure = commit(routine: nil) { return failure }
            return .rejected("routine \(routineID) not found")
        }
        guard updates.allSatisfy({ belongsToRoutine($0.target, routine: routine) }) else {
            if let failure = commit(routine: nil) { return failure }
            return .rejected("template-only update targets a row outside routine \(routineID)")
        }
        apply(updates)
        if let failure = commit(routine: routine) { return failure }
        return .applied
    }

    /// Mixed-version terminal rejection: preserve/dedupe history, explicitly
    /// record that template intent was not applied, and commit once without
    /// touching the routine.
    func executeHistoryOnlyRejection(_ workout: IncomingWatchWorkout) -> Outcome {
        let session: WorkoutSession
        switch historyService.stageHistory(workout) {
        case .duplicate(let existing):
            session = existing
        case .staged(let staged):
            session = staged
        }
        session.didUpdateTemplate = false
        if let failure = commit(routine: nil) { return failure }
        NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
        return .rejected("unsequenced template intent is older than sequenced authority")
    }

    // MARK: - Validation

    /// One validated set mutation. Resolved before any mutation happens so the
    /// whole request can be rejected atomically.
    struct SetUpdate {
        enum Target {
            case routineSet(ExerciseSet)
            case alternativeSet(AlternativeExerciseSet)
        }
        let target: Target
        let reps: Int
        let weight: Double
    }

    private enum Validation {
        case success([SetUpdate])
        case failure(String)
    }

    private func validate(_ workout: IncomingWatchWorkout, against routine: Routine?) -> Validation {
        guard let routine else {
            return .failure("routine \(workout.routineId) not found")
        }

        var updates: [SetUpdate] = []
        for completedExercise in workout.exercises {
            let modifiedSets = completedExercise.sets.filter {
                $0.actualReps != $0.plannedReps || $0.actualWeight != $0.plannedWeight
            }
            guard !modifiedSets.isEmpty else { continue }

            guard let routineExercise = routine.routineExercisesList
                .first(where: { $0.id == completedExercise.id }) else {
                return .failure("routine exercise \(completedExercise.id) not found")
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
        return .success(updates)
    }

    // MARK: - Mutation + commit

    private func apply(_ updates: [SetUpdate]) {
        for update in updates {
            switch update.target {
            case .routineSet(let set):
                set.reps = update.reps
                set.weight = update.weight
            case .alternativeSet(let set):
                set.reps = update.reps
                set.weight = update.weight
            }
        }
    }

    private func markAtomicOutcome(
        _ outcome: TemplateTransactionOutcome,
        transactionID: UUID?,
        on session: WorkoutSession
    ) {
        guard let transactionID else { return }
        session.watchTemplateTransactionID = transactionID
        session.watchTemplateOutcomeRaw = outcome.rawValue
    }

    private func belongsToRoutine(_ target: SetUpdate.Target, routine: Routine) -> Bool {
        switch target {
        case .routineSet(let set):
            return routine.routineExercisesList.contains { exercise in
                exercise.setsList.contains { $0.id == set.id }
            }
        case .alternativeSet(let set):
            return routine.routineExercisesList.contains { exercise in
                exercise.alternativesList.contains { alternative in
                    alternative.setsList.contains { $0.id == set.id }
                }
            }
        }
    }

    /// The single `save()`. Returns a failure outcome, or nil on success.
    private func commit(routine: Routine?) -> Outcome? {
        routine?.updatedAt = Date()
        do {
            try workoutSessionRepository.save()
            return nil
        } catch {
            print("Template transaction save failed: \(error)")
            return .saveFailed(error)
        }
    }

    /// The routine this transaction targets, with legacy placeholder rows
    /// treated as absent.
    ///
    /// An older build inserted a placeholder `Routine` when ingesting a
    /// workout whose routine had been deleted, which resurrected the deleted
    /// template and re-synced it to the watch. Such a row is repaired (deleted)
    /// only under the strict contradiction signature — created after the
    /// workout ended, named exactly like the workout's routine, no exercises,
    /// and no schedule. Name or emptiness alone is deliberately insufficient:
    /// a real, still-empty routine the user just created must never be deleted.
    private func liveRoutine(for workout: IncomingWatchWorkout) -> Routine? {
        guard let routine = routineRepository.fetch(id: workout.routineId) else { return nil }
        let isLegacyPlaceholder = routine.createdAt > workout.endTime
            && routine.name == workout.routineName
            && routine.routineExercisesList.isEmpty
            && routine.schedule == nil
        guard isLegacyPlaceholder else { return routine }
        print("Removing legacy placeholder routine \(routine.id) resurrected for workout \(workout.id)")
        routineRepository.delete(routine)
        return nil
    }
}
