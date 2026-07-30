//
//  WatchWorkoutViewModel+ProgressiveOverloadApply.swift
//  GymStreakWatch Watch App
//
//  The apply half of mid-workout progressive overload (ticket 04), split out of
//  `WatchWorkoutViewModel+ProgressiveOverload.swift` to keep both files within
//  the repository's file-length convention. That file owns the presentation
//  state, qualification, and target resolution; this one owns the single deep
//  operation the UI calls and its auto-finish coordination.
//
//  ORDER OF OPERATIONS IS THE CONTRACT. Nothing observable happens until the
//  transaction is durable: the atomic sync-state write comes first, and only
//  after it succeeds do the active workout mutate, the success haptic play, the
//  confirmation appear, and transport be attempted. A failed write leaves the
//  suggestion actionable and mutates nothing.
//

import Foundation
import WatchKit

extension WatchWorkoutViewModel {

    // MARK: - Apply

    /// The single deep operation the UI calls.
    ///
    /// Repeated taps while applying are ignored and, because the transaction id
    /// is minted once per slot and reused, a retry after a transport failure
    /// reuses the exact same transaction rather than allocating a second one.
    func applyProgressiveOverload(slotID: UUID, increment: Double) {
        // A repeat tap while an apply is in flight is ignored outright.
        if case .applying = overloadPresentation { return }
        overloadErrorMessage = nil
        setOverloadPresentation(.applying(slotID: slotID))
        performProgressiveOverloadApply(slotID: slotID, increment: increment)
    }

    private func performProgressiveOverloadApply(slotID: UUID, increment: Double) {
        // 1. Re-resolve by stable UUID and reject once the terminal transition
        //    has begun. Everything below re-reads live state; nothing captured
        //    when the suggestion appeared is trusted.
        guard qualifiesForProgressiveOverload(slotID: slotID),
              let exerciseIndex = exercises.firstIndex(where: { $0.id == slotID }),
              let routineID = currentRoutine?.id else {
            // The target vanished mid-flow. Release the finish condition the
            // suggestion was holding back rather than stranding the workout
            // waiting for a manual End.
            setOverloadPresentation(.none)
            resumeAutoFinishAfterOverloadFlow()
            return
        }
        let exercise = exercises[exerciseIndex]
        guard let targetRepMin = exercise.targetRepMin else {
            setOverloadPresentation(.none)
            resumeAutoFinishAfterOverloadFlow()
            return
        }

        // 2. Resolve the template scheme from the shared effective-routine
        //    projection by stable IDs — never from the active workout's
        //    performed values, and never by display name.
        guard let target = resolveOverloadTemplateTarget(for: exercise, routineID: routineID) else {
            overloadErrorMessage = String(
                localized: "This exercise is no longer part of the routine on iPhone.",
                comment: "Shown when a mid-workout overload target cannot be resolved in the routine"
            )
            setOverloadPresentation(.suggestion(slotID: slotID))
            return
        }

        // 3. Compute absolute proposed values for EVERY template set, including
        //    counterweight-assistance subtraction clamped at zero.
        let loadBehavior = ExerciseLoadBehavior.from(raw: exercise.loadBehaviorRaw)
        let increase = ProgressiveOverloadService.applyIncrease(
            toWeights: target.sets.map(\.weight),
            increment: increment,
            targetRepMin: targetRepMin,
            loadBehavior: loadBehavior
        )
        let setChanges = zip(target.sets, increase.weights).map { set, newWeight in
            WatchTemplateSetChange(
                setID: set.id,
                expectedReps: set.reps,
                expectedWeight: set.weight,
                proposedReps: increase.reps,
                proposedWeight: newWeight
            )
        }
        let intent = WatchProgressiveOverloadIntent(
            routineExerciseID: slotID,
            alternativeID: target.alternativeID,
            targetRepMin: targetRepMin,
            setChanges: setChanges
        )
        guard intent.isWellFormed else {
            overloadErrorMessage = String(
                localized: "The weight increase could not be prepared.",
                comment: "Shown when a mid-workout overload intent fails its own validation"
            )
            setOverloadPresentation(.suggestion(slotID: slotID))
            return
        }

        // 4. One stable transaction id per slot, so a retry never allocates a
        //    second sequence.
        let transactionID = pendingOverloadTransactionIDs[slotID] ?? UUID()
        pendingOverloadTransactionIDs[slotID] = transactionID

        // 5. THE durability boundary. The exact bytes, the FIFO position, the
        //    per-routine sequence, the held routine anchor, and (through the
        //    fold) the optimistic overlay all commit in one atomic replacement
        //    BEFORE transport or any success UI.
        do {
            try connectivityManager.syncState.enqueue(
                progressiveOverload: intent,
                routineID: routineID,
                transactionID: transactionID,
                routineAnchor: currentRoutine
            )
        } catch {
            // Nothing was enqueued and no counter was consumed: keep the
            // suggestion actionable rather than claiming a durable change.
            print("WatchWorkoutViewModel: overload transaction write failed — \(error.localizedDescription)")
            overloadErrorMessage = String(
                localized: "Could not save the weight increase. Please try again.",
                comment: "Shown when the durable write for a mid-workout overload fails"
            )
            setOverloadPresentation(.suggestion(slotID: slotID))
            return
        }

        // 6. Durable from here on. Mirror the iOS overload exactly: the
        //    performance moves into the planned values and the next workout's
        //    target into the actual ones. `overloadAppliedExerciseIDs` on the
        //    completed payload is what tells iOS to set
        //    `progressiveOverloadApplied`, which is what makes every aggregator
        //    read the planned (i.e. performed) values back out.
        let workoutIncrease = ProgressiveOverloadService.applyIncrease(
            toWeights: exercises[exerciseIndex].sets.map(\.actualWeight),
            increment: increment,
            targetRepMin: targetRepMin,
            loadBehavior: loadBehavior
        )
        for (setIndex, newWeight) in workoutIncrease.weights.enumerated() {
            var set = exercises[exerciseIndex].sets[setIndex]
            set.plannedReps = set.actualReps
            set.plannedWeight = set.actualWeight
            set.actualReps = workoutIncrease.reps
            set.actualWeight = newWeight
            exercises[exerciseIndex].sets[setIndex] = set
        }
        appliedOverloadSlots[slotID] = transactionID
        deferredOverloadSlotIDs.remove(slotID)
        persistActiveCheckpoint()

        // 7. Transport is best-effort; the durable transaction is what
        //    guarantees delivery. A transient failure simply leaves it pending.
        connectivityManager.transportEligibleWorkouts()

        // 8. Success feedback only now — after the commit, never before it.
        WKInterfaceDevice.current().play(.success)
        setOverloadPresentation(.confirmation(
            slotID: slotID,
            newWeight: increase.weights.first ?? 0,
            targetRepMin: targetRepMin
        ))
    }

    // MARK: - Auto-finish coordination

    /// A qualifying FINAL set opens the suggestion instead of finishing, so the
    /// delayed auto-finish must be revoked — never left to fire underneath the
    /// surface. Apply or Later resumes the check exactly once.
    func cancelAutoFinishForOverloadFlow() {
        autoFinishTask?.cancel()
        autoFinishTask = nil
    }

    /// Internal (not private) so the invalidation paths in
    /// `+ProgressiveOverload.swift` can release a finish condition the
    /// suggestion was holding back.
    func resumeAutoFinishAfterOverloadFlow() {
        guard !isEnding, isWorkoutActive, !isWorkoutFrozen else { return }
        guard findNextIncompleteSet() == nil else { return }
        // Re-enter the existing single auto-finish path rather than starting a
        // second, unretained finish task.
        autoFinishWorkout()
    }
}
