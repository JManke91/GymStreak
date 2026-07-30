//
//  WatchWorkoutViewModel+Recovery.swift
//  GymStreakWatch Watch App
//
//  Ticket 08 (in-workout routine editing): the active-workout checkpoint writer
//  and the two resume paths, extracted from WatchWorkoutViewModel to keep that
//  file from growing further (mirrors WatchWorkoutViewModel+StructuralEditing).
//  Driven by WatchWorkoutRecoveryCoordinator after process termination.
//

import Foundation

extension WatchWorkoutViewModel {
    /// Writes the app-owned active-workout checkpoint so the workout survives
    /// watchOS terminating GymStreak mid-session. Best effort — a failed write
    /// costs at most one mutation's worth of resume fidelity, never the workout
    /// — so it is called at bounded meaningful mutations (start, set completion,
    /// value/rest edits, swaps, add/remove, navigation) and never on sensor
    /// samples. Suspended once finalization begins (`isEnding`): the frozen
    /// durable payload then owns the workout and recovery keys off it.
    func persistActiveCheckpoint() {
        guard !isUITesting, isWorkoutActive, !isEnding,
              let routine = currentRoutine,
              let startTime = workoutStartTime,
              let workoutID = pendingCompletedWorkoutId,
              let healthKitID = pendingHealthKitWorkoutId,
              let baseline = structuralBaseline else { return }
        let checkpoint = WatchActiveWorkoutCheckpoint(
            workoutID: workoutID,
            healthKitWorkoutID: healthKitID,
            routine: routine,
            exercises: exercises,
            currentExerciseIndex: currentExerciseIndex,
            currentSetIndex: currentSetIndex,
            startTime: startTime,
            structuralBaseline: baseline,
            // Ticket 04: enough to rederive a safe overload state after
            // relaunch without re-prompting or applying twice. Transient
            // presentation (picker position, confirmation animation) is
            // deliberately not checkpointed.
            appliedOverloads: appliedOverloadSlots.map {
                WatchActiveWorkoutCheckpoint.AppliedOverload(slotID: $0.key, transactionID: $0.value)
            },
            deferredOverloadSlotIDs: Array(deferredOverloadSlotIDs)
        )
        do {
            try checkpointStore.save(checkpoint)
        } catch {
            print("WatchWorkoutViewModel: active checkpoint write failed — \(error.localizedDescription)")
        }
    }

    /// Rebuilds this view model from a durable checkpoint after process
    /// termination interrupted a LIVE (pre-finalization) workout. The recovered
    /// HealthKit session (if any) was already adopted by the coordinator;
    /// `hasLiveSession` drives whether live metrics resume. Idempotent: a second
    /// recovery signal for the same session is a no-op.
    func resumeRecoveredWorkout(from checkpoint: WatchActiveWorkoutCheckpoint, hasLiveSession: Bool) {
        guard !isWorkoutActive else { return }
        currentRoutine = checkpoint.routine
        exercises = checkpoint.exercises
        structuralBaseline = checkpoint.structuralBaseline
        pendingCompletedWorkoutId = checkpoint.workoutID
        pendingHealthKitWorkoutId = checkpoint.healthKitWorkoutID
        workoutStartTime = checkpoint.startTime

        // Clamp restored indices against the recovered exercise list.
        if exercises.isEmpty {
            currentExerciseIndex = 0
            currentSetIndex = 0
        } else {
            currentExerciseIndex = min(max(checkpoint.currentExerciseIndex, 0), exercises.count - 1)
            let setCount = exercises[currentExerciseIndex].sets.count
            currentSetIndex = setCount == 0 ? 0 : min(max(checkpoint.currentSetIndex, 0), setCount - 1)
        }

        isEnding = false
        isWorkoutInputSuspended = false
        pendingExerciseSelection = nil
        workoutSummary = nil

        // Ticket 04: restore applied/deferred overload bookkeeping so recovery
        // never re-prompts for a target that was already handled, and never
        // allocates a second transaction for one already applied. The surface
        // itself comes back as `.none` — a suggestion is re-derived from live
        // state if the target still qualifies, and a confirmation is transient.
        appliedOverloadSlots = Dictionary(
            uniqueKeysWithValues: checkpoint.appliedOverloads.map { ($0.slotID, $0.transactionID) }
        )
        pendingOverloadTransactionIDs = appliedOverloadSlots
        deferredOverloadSlotIDs = Set(checkpoint.deferredOverloadSlotIDs)
        overloadPresentation = .none
        overloadErrorMessage = nil
        isWorkoutActive = true
        workoutState = hasLiveSession ? .running : .started

        // The recovered session/builder carries no app metadata; restore the
        // finalization metadata source so a later End stamps the correct
        // external-UUID / routine metadata.
        healthKitManager.restoreRoutineMetadata(routineName: checkpoint.routine.name, routineId: checkpoint.routine.id)
        if hasLiveSession {
            Task { await donateActionButtonIntent() }
        }

        // Signal RoutineListView to re-present the active-workout cover.
        resumedWorkoutRoutineID = checkpoint.routine.id
        print("WatchWorkoutViewModel: resumed live workout \(checkpoint.workoutID) (liveSession: \(hasLiveSession))")
    }

    /// Resumes ONLY the terminal finalization of a workout whose durable payload
    /// froze before the crash — never reopens editing or rebuilds the payload.
    /// Re-enters the finalizer with the frozen bytes: with a recovered live
    /// session it finishes the exact HealthKit workout (also ending a still
    /// -running session so it cannot leak); with none it promotes the durable
    /// payload so the workout still reaches iOS. Reentrance is rejected by the
    /// finalizer itself.
    func resumeInterruptedFinalization(workoutID: UUID) async {
        guard let entry = connectivityManager.syncState.entry(id: workoutID),
              let workout = entry.completedWorkout,
              entry.phase == .awaitingHealthKitMetadata || entry.phase == .awaitingHealthKitFinish else {
            // Already past HealthKit (or gone) — only a stale checkpoint remains.
            checkpointStore.clear()
            return
        }
        // Restore the metadata a fresh process lost so finish stamps the correct
        // external UUID / routine metadata.
        healthKitManager.restoreRoutineMetadata(routineName: workout.routineName, routineId: workout.routineId)
        let healthKit: WorkoutFinalizationHealthKit? = isUITesting ? nil : healthKitManager
        let outcome = await finalizer.finalize(
            workout,
            healthKit: healthKit,
            onTransportEligible: { [connectivityManager] in connectivityManager.transportEligibleWorkouts() }
        )
        if case .completed = outcome {
            checkpointStore.clear()
        }
        print("WatchWorkoutViewModel: resumed interrupted finalization \(workoutID) — outcome \(outcome)")
    }
}
