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
    /// **Only `resolvedExercises` reach it.** A row the person has not yet pointed at a
    /// library exercise has no library exercise to write, and this app does not invent
    /// one — it is left out, and the sheet says so before Create is tapped.
    ///
    /// `order` is assigned from position among the resolved exercises, never carried over
    /// from an edit: the draft's array order is what the sheet showed — after any move —
    /// and this is where it becomes the routine's stored `order`, with the gaps left by
    /// unresolved rows closed up.
    ///
    /// - Parameter edits: exercises the person reopened in `ConfigureExerciseSetsView`,
    ///   keyed by drafted-row id. An edited row writes exactly what that screen returned;
    ///   every other row writes its drafted scheme.
    func pendingExercises(
        applying edits: [UUID: PendingRoutineExercise] = [:]
    ) -> [PendingRoutineExercise] {
        resolvedExercises.enumerated().compactMap { index, drafted in
            guard var pending = edits[drafted.id] ?? drafted.pendingExercise(order: index) else {
                return nil
            }
            pending.order = index
            return pending
        }
    }
}

extension GroundedDraftExercise {

    /// This drafted exercise's own scheme as a pending exercise, or `nil` while it is
    /// unresolved. Also what `ConfigureExerciseSetsView` is seeded with the first time the
    /// row is opened.
    ///
    /// The sets are identical by construction — a drafted exercise carries one set scheme,
    /// repeated. Alternatives and rep-range goals are deliberately left empty: nothing in a
    /// typed description expresses them, and inventing either would be the app guessing on
    /// the person's behalf at the exact moment it writes to their store. The person can
    /// add both by opening the row.
    func pendingExercise(order: Int) -> PendingRoutineExercise? {
        guard let exercise else { return nil }
        return PendingRoutineExercise(
            exercise: exercise,
            sets: (0..<setCount).map { setOrder in
                ExerciseSet(
                    reps: reps,
                    weight: weightKilograms,
                    restTime: RoutineDraftGrounder.defaultRestTime,
                    order: setOrder
                )
            },
            order: order
        )
    }
}
