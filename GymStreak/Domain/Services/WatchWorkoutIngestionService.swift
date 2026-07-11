//
//  WatchWorkoutIngestionService.swift
//  GymStreak
//
//  Materializes a completed watch workout (`.watchWorkoutCompleted` payload)
//  into a `WorkoutSession`, including dedup against already-ingested
//  sessions and the optional routine-template update. Constructor-injected
//  with the Domain repository protocols it needs, and consumes the Domain
//  `IncomingWatchWorkout` model — no dependency on any concrete Data type
//  (the Data layer maps its wire DTO into that model at the sync boundary).
//  `RoutinesViewModel` owns the NotificationCenter
//  subscription and the watch-ack side effects (it already owns `watchSync`);
//  this service reports back what it did via `Result` so the ViewModel knows
//  whether to ack and whether to refresh its `routines` list.
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
        /// Whether the caller should ack + mark-processed with the watch.
        /// True for the duplicate-skip path and a successful session save;
        /// false only when the SwiftData save itself failed, so the workout
        /// stays in the durable pending buffer and is retried later.
        let shouldAcknowledge: Bool
        /// Whether the routine template was edited in place, meaning the
        /// caller's cached routine list needs refetching.
        let templateWasUpdated: Bool
    }

    /// Mirrors the original `RoutinesViewModel.handleCompletedWatchWorkout` logic 1:1.
    func ingest(_ workout: IncomingWatchWorkout) -> Result {
        print("Received completed watch workout: \(workout.routineName)")

        // Step 1: Create WorkoutSession to appear in history
        // Idempotency: if this workout has already been ingested (e.g. from a
        // watch-side retry after a previously dropped transferUserInfo), skip
        // re-inserting. We match on the workout's UUID first, then on the
        // healthKitWorkoutId as a secondary key (covers cross-device cases
        // where the iOS-stored id might differ but HK metadata aligns).
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
                return Result(shouldAcknowledge: true, templateWasUpdated: false)
            }
        }

        // Find the routine by ID
        let routine = routineRepository.fetch(id: workout.routineId)

        // Create workout session — preserve the watch-generated id so retries
        // are detectable above and to keep iOS/watch in agreement on identity.
        let workoutSession = WorkoutSession(routine: routine ?? createPlaceholderRoutine(from: workout))
        workoutSession.id = workout.id
        workoutSession.startTime = workout.startTime
        workoutSession.endTime = workout.endTime
        workoutSession.didUpdateTemplate = workout.shouldUpdateTemplate
        workoutSession.routineName = workout.routineName
        workoutSession.healthKitWorkoutId = workout.healthKitWorkoutId

        // Create workout exercises
        for completedExercise in workout.exercises {
            let workoutExercise = WorkoutExercise(
                exerciseName: completedExercise.name,
                muscleGroups: [completedExercise.muscleGroup],
                order: completedExercise.order,
                exerciseId: completedExercise.exerciseId,
                loadBehavior: ExerciseLoadBehavior(rawValue: completedExercise.loadBehaviorRaw) ?? .resistance
            )
            workoutExercise.workoutSession = workoutSession
            // Copy superset fields from completed exercise
            workoutExercise.supersetId = completedExercise.supersetId
            workoutExercise.supersetOrder = completedExercise.supersetOrder
            // Copy rep range fields from completed exercise
            workoutExercise.targetRepMin = completedExercise.targetRepMin
            workoutExercise.targetRepMax = completedExercise.targetRepMax
            // Copy alternative-swap metadata (name/exerciseId already reflect what was performed)
            workoutExercise.plannedExerciseId = completedExercise.plannedExerciseId
            workoutExercise.plannedExerciseName = completedExercise.plannedExerciseName

            // Create workout sets
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
        var shouldAcknowledge = false
        do {
            try workoutSessionRepository.save()
            print("Created workout session from watch workout: \(workout.routineName)")
            shouldAcknowledge = true
            // Notify any view models cached on the History tab to refresh.
            NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
        } catch {
            // Leave the workout in the persistent pending buffer so we retry on
            // next app launch / observer registration. Do NOT report success.
            print("Error creating workout session from watch workout: \(error)")
        }

        // Step 2: Optionally update routine template
        guard workout.shouldUpdateTemplate else {
            print("Not updating template - user chose not to update")
            return Result(shouldAcknowledge: shouldAcknowledge, templateWasUpdated: false)
        }

        guard let templateRoutine = routineRepository.fetch(id: workout.routineId) else {
            print("Could not find routine with ID: \(workout.routineId)")
            return Result(shouldAcknowledge: shouldAcknowledge, templateWasUpdated: false)
        }

        print("Updating template for routine: \(templateRoutine.name)")
        var updatedAny = false

        // Update each routine exercise's sets with the actual values
        for completedExercise in workout.exercises {
            guard let routineExercise = templateRoutine.routineExercisesList.first(where: { $0.id == completedExercise.id }) else {
                print("Could not find routine exercise with ID: \(completedExercise.id)")
                continue
            }

            for completedSet in completedExercise.sets {
                guard let set = routineExercise.setsList.first(where: { $0.id == completedSet.id }) else {
                    print("Could not find set with ID: \(completedSet.id)")
                    continue
                }

                // Only update if the set was modified
                if completedSet.actualReps != completedSet.plannedReps ||
                   completedSet.actualWeight != completedSet.plannedWeight {
                    set.reps = completedSet.actualReps
                    set.weight = completedSet.actualWeight
                    updatedAny = true
                    print("Updated set: \(completedSet.actualWeight)lbs × \(completedSet.actualReps) reps")
                }
            }
        }

        guard updatedAny else {
            print("No sets were actually modified")
            return Result(shouldAcknowledge: shouldAcknowledge, templateWasUpdated: false)
        }

        templateRoutine.updatedAt = Date()
        do {
            try routineRepository.save()
            print("Template updated successfully - \(workout.modifiedSetsCount) sets modified")
        } catch {
            print("Error saving context: \(error)")
        }
        return Result(shouldAcknowledge: shouldAcknowledge, templateWasUpdated: true)
    }

    // Helper method to create a placeholder routine if the original was deleted
    private func createPlaceholderRoutine(from workout: IncomingWatchWorkout) -> Routine {
        let routine = Routine(name: workout.routineName)
        routine.id = workout.routineId
        return routine
    }
}
