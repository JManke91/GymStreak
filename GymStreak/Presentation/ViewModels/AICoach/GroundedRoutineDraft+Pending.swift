//
//  GroundedRoutineDraft+Pending.swift
//  GymStreak
//
//  The last step before a drafted routine becomes a real one: the grounded draft
//  expressed as the `PendingRoutineExercise` list `RoutinesViewModel.createRoutine`
//  already takes. See docs/ai-coach-routine-drafting.md.
//
//  It lives in `Presentation/` because `PendingRoutineExercise` does — `Domain/` has no
//  business knowing about the create-routine flow's transfer type.
//

import Foundation

extension GroundedRoutineDraft {

    /// The draft as the create-routine transaction's input.
    ///
    /// `order` is assigned from the draft's own position, not from anything the model
    /// produced: the schema asks for the exercises in the order the description lists
    /// them, and this is where that ordering becomes the routine's ordering. The sets are
    /// identical by construction — a drafted exercise carries one set scheme, repeated —
    /// and ticket 05 is what makes them differ.
    ///
    /// Alternatives and rep-range goals are deliberately left empty. Nothing in a typed
    /// description expresses them, and inventing either would be the app guessing on the
    /// person's behalf at the exact moment it writes to their store.
    func pendingExercises() -> [PendingRoutineExercise] {
        exercises.enumerated().map { index, drafted in
            PendingRoutineExercise(
                exercise: drafted.exercise,
                sets: (0..<drafted.setCount).map { order in
                    ExerciseSet(
                        reps: drafted.reps,
                        weight: drafted.weightKilograms,
                        restTime: RoutineDraftGrounder.defaultRestTime,
                        order: order
                    )
                },
                order: index
            )
        }
    }
}
