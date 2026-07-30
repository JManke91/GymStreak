//
//  WatchWorkoutIngestionService.swift
//  GymStreak
//
//  Materializes a completed watch workout into a `WorkoutSession`, including
//  dedup against already-ingested sessions. Constructor-injected with the
//  Domain repository protocols it needs, and consumes the Domain
//  `IncomingWatchWorkout` model — no dependency on any concrete Data type (the
//  Data layer maps its wire DTO into that model at the sync boundary).
//
//  Since ticket 04 the caller is `WatchWorkoutIngestionCoordinator`
//  (composition root), which owns the durable inbox drain, receipts, and watch
//  acknowledgment side effects, and constructs this service over an isolated
//  single-save transaction's repositories. Since ticket 05 the routine
//  template update is no longer part of this service: a requested template
//  update is a transaction (`WatchTemplateTransactionService`) that stages its
//  history through `stageHistory` and commits both halves in ONE save.
//

import Foundation

@MainActor
final class WatchWorkoutIngestionService {
    private let routineRepository: RoutineRepository
    private let workoutSessionRepository: WorkoutSessionRepository

    init(routineRepository: RoutineRepository, workoutSessionRepository: WorkoutSessionRepository) {
        self.routineRepository = routineRepository
        self.workoutSessionRepository = workoutSessionRepository
    }

    /// Outcome of ingesting one completed watch workout.
    struct Result {
        /// Whether the caller should acknowledge to the watch. True for the
        /// duplicate-skip path and a successful session save; false only when
        /// the SwiftData save itself failed, so the workout stays in the
        /// durable inbox and is retried later.
        let shouldAcknowledge: Bool
    }

    /// Result of staging history into the (uncommitted) context.
    enum StageResult {
        /// Already ingested under the same id — nothing staged.
        case duplicate(WorkoutSession)
        case staged(WorkoutSession)
    }

    /// Idempotently ingests one completed no-template watch workout: stage
    /// history, then commit the isolated context exactly once.
    func ingest(_ workout: IncomingWatchWorkout) -> Result {
        print("Received completed watch workout: \(workout.routineName)")

        guard case .staged = stageHistory(workout) else {
            return Result(shouldAcknowledge: true)
        }

        do {
            try workoutSessionRepository.save()
            print("Created workout session from watch workout: \(workout.routineName)")
            // Notify any view models cached on the History tab to refresh.
            NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
            return Result(shouldAcknowledge: true)
        } catch {
            // Leave the workout in the durable inbox so we retry on the next
            // drain. Do NOT report success.
            print("Error creating workout session from watch workout: \(error)")
            return Result(shouldAcknowledge: false)
        }
    }

    /// Materializes the denormalized history graph into the injected
    /// repositories WITHOUT saving, so a caller can commit it together with a
    /// routine template mutation in one transaction.
    ///
    /// Idempotency: if this workout has already been ingested (e.g. from a
    /// watch-side retry after a previously dropped transfer), nothing is
    /// staged. We match on the workout's UUID first, then on the
    /// healthKitWorkoutId as a secondary key (covers cross-device cases where
    /// the iOS-stored id might differ but HK metadata aligns).
    @discardableResult
    func stageHistory(_ workout: IncomingWatchWorkout) -> StageResult {
        if let existing = workoutSessionRepository.findSession(id: workout.id, healthKitWorkoutId: workout.healthKitWorkoutId) {
            if existing.id != workout.id {
                // Matched by healthKitWorkoutId under a *different* session id:
                // this session was reconstructed from HealthKit by the recovery
                // banner (template values guessed as actuals) before the real
                // payload arrived. Real ingests always preserve the watch id, so
                // an id mismatch uniquely identifies a placeholder. Replace it
                // with the actual per-set data instead of dropping the payload —
                // skipping here is what permanently lost the recorded values.
                print("Replacing reconstructed placeholder session \(existing.id) with real watch payload \(workout.id)")
                workoutSessionRepository.delete(existing)
            } else {
                print("Skipping duplicate watch workout: \(workout.routineName) (existing session id=\(existing.id))")
                return .duplicate(existing)
            }
        }

        // Find the routine by ID. A missing routine (deleted since the watch
        // cached it) produces denormalized history with `routine == nil` —
        // never a placeholder Routine, which would resurrect the deleted
        // template (and reach the watch again via routine sync).
        let routine = routineRepository.fetch(id: workout.routineId)

        // Create workout session — preserve the watch-generated id so retries
        // are detectable above and to keep iOS/watch in agreement on identity.
        let workoutSession = WorkoutSession(routine: routine)
        workoutSession.id = workout.id
        workoutSession.startTime = workout.startTime
        workoutSession.endTime = workout.endTime
        workoutSession.didUpdateTemplate = false
        workoutSession.routineName = workout.routineName
        workoutSession.healthKitWorkoutId = workout.healthKitWorkoutId

        // Targets the watch applied progressive overload to during this workout
        // (ticket 04). The watch mirrors `WorkoutViewModel.applyProgressiveOverload`
        // before freezing: the performance is stored in the `planned*` values and
        // the next workout's target in `actual*`. This flag is what tells every
        // aggregator (volume, charts, records, AI Coach) to read `planned*`, so
        // it must be set for exactly those exercises or history would report the
        // new target as the performed work.
        let overloadAppliedIDs = Set(workout.overloadAppliedExerciseIDs)

        for completedExercise in workout.exercises {
            let workoutExercise = WorkoutExercise(
                exerciseName: completedExercise.name,
                muscleGroups: [completedExercise.muscleGroup],
                order: completedExercise.order,
                exerciseId: completedExercise.exerciseId,
                routineExerciseId: completedExercise.id,
                loadBehavior: ExerciseLoadBehavior(rawValue: completedExercise.loadBehaviorRaw) ?? .resistance
            )
            workoutExercise.workoutSession = workoutSession
            workoutExercise.supersetId = completedExercise.supersetId
            workoutExercise.supersetOrder = completedExercise.supersetOrder
            workoutExercise.targetRepMin = completedExercise.targetRepMin
            workoutExercise.targetRepMax = completedExercise.targetRepMax
            // Alternative-swap metadata (name/exerciseId already reflect what was performed)
            workoutExercise.plannedExerciseId = completedExercise.plannedExerciseId
            workoutExercise.plannedExerciseName = completedExercise.plannedExerciseName
            workoutExercise.progressiveOverloadApplied = overloadAppliedIDs.contains(completedExercise.id)

            for completedSet in completedExercise.sets {
                let workoutSet = WorkoutSet(
                    plannedReps: completedSet.plannedReps,
                    actualReps: completedSet.actualReps,
                    plannedWeight: completedSet.plannedWeight,
                    actualWeight: completedSet.actualWeight,
                    restTime: completedSet.restTime,
                    order: completedSet.order
                )
                workoutSet.isCompleted = completedSet.isCompleted
                workoutSet.completedAt = completedSet.completedAt
                workoutSet.workoutExercise = workoutExercise
                workoutExercise.sets?.append(workoutSet)
                workoutSessionRepository.insert(workoutSet)
            }

            workoutSession.workoutExercises?.append(workoutExercise)
            workoutSessionRepository.insert(workoutExercise)
        }

        workoutSessionRepository.insert(workoutSession)
        return .staged(workoutSession)
    }
}
