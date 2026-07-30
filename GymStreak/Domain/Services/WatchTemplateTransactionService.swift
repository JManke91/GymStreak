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

    let routineRepository: RoutineRepository
    let workoutSessionRepository: WorkoutSessionRepository
    /// Library used to resolve a Watch-added exercise (ticket 07). Bound to the
    /// same isolated context as the routine, so a resolved `Exercise` links to
    /// the new `RoutineExercise` and commits in this transaction's single save.
    let exerciseRepository: ExerciseRepository
    private let historyService: WatchWorkoutIngestionService

    init(
        routineRepository: RoutineRepository,
        workoutSessionRepository: WorkoutSessionRepository,
        exerciseRepository: ExerciseRepository
    ) {
        self.routineRepository = routineRepository
        self.workoutSessionRepository = workoutSessionRepository
        self.exerciseRepository = exerciseRepository
        self.historyService = WatchWorkoutIngestionService(
            routineRepository: routineRepository,
            workoutSessionRepository: workoutSessionRepository
        )
    }

    /// Completed-workout kind: denormalized history and the complete template
    /// update — set values PLUS explicit structural add/remove intent
    /// (ticket 07) — stage in the same isolated context and commit in ONE save.
    /// The entire request is validated before any mutation, so a missing
    /// routine, an unresolvable added exercise, or malformed membership intent
    /// rejects the whole request (history still saved, routine untouched)
    /// instead of applying part of it. Only explicit intent is merged against
    /// the CURRENT routine, so concurrent iOS edits win unless the watch
    /// explicitly added or removed that exact slot.
    func execute(_ workout: IncomingWatchWorkout) -> Outcome {
        let routine = liveRoutine(for: workout)

        // Validate the complete request first — no partial updates.
        let plan: MergePlan
        var rejection: String?
        switch validateMerge(workout, against: routine) {
        case .failure(let reason):
            plan = .empty
            rejection = reason
        case .success(let resolved):
            plan = resolved
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
            // idempotent upgrade reconciliation required by the protocol. The
            // structural merge below is itself idempotent (minted-slot-absent
            // guard, already-absent removals, value-set updates).
            session = existing
        case .staged(let staged):
            session = staged
        }

        if rejection == nil, let routine {
            apply(plan.setUpdates)
            applyStructural(plan, to: routine)
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
        print("Template transaction applied: \(plan.setUpdates.count) set(s), +\(plan.additions.count)/-\(plan.removals.count) exercise(s) on '\(workout.routineName)'")
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

    // MARK: - Mutation + commit

    /// Internal (not private) so the progressive-overload kind in
    /// `+ProgressiveOverload.swift` stages through this exact code path rather
    /// than growing a second mutation routine.
    func apply(_ updates: [SetUpdate]) {
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
    /// Internal (not private) so every transaction kind, including the
    /// progressive-overload extension, commits through this one boundary.
    func commit(routine: Routine?) -> Outcome? {
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
