//
//  SupersetEditor.swift
//  GymStreak
//
//  Pure set-algebra for the routine-detail superset editor. Diffs a pending
//  selection against a superset's current membership and decides which
//  link/unlink/create/dissolve operation applies — without touching
//  persistence. `RoutinesViewModel` asks for the decision and performs the
//  actual mutation + save + watch-sync side effects via its existing
//  `createSuperset`/`addExerciseToSuperset`/`removeExerciseFromSuperset`/
//  `dissolveSuperset` methods (also called directly by views, so they stay
//  put on the ViewModel).
//

import Foundation

/// Whether the superset editor is creating a brand-new superset or modifying
/// the membership of an existing one. Drives `RoutinesViewModel.applySupersetEdit`.
enum SupersetEditMode: Equatable {
    case editing(UUID)    // Editing existing superset (supersetId)
    case creating         // Creating new superset from scratch
}

/// The minimal operation `RoutinesViewModel.applySupersetEdit` should perform
/// for a given mode + selection, as decided by `SupersetEditor.decideEdit`.
enum SupersetEditDecision {
    /// Selection dropped to 0 or 1 member — dissolve the whole superset.
    case dissolve(supersetId: UUID)
    /// Selection changed against an existing superset's membership.
    case modify(supersetId: UUID, toAdd: Set<UUID>, toRemove: Set<UUID>)
    /// Create a brand-new superset from the given (order-sorted) exercises.
    case create(exercises: [RoutineExercise])
    /// Nothing to do (no mode, or a "creating" selection with < 2 members).
    case none
}

enum SupersetEditor {
    /// Whether the "Done" action in the superset editor should be enabled.
    static func canApplyEdit(_ mode: SupersetEditMode?, selection: Set<UUID>) -> Bool {
        switch mode {
        case .creating:
            return selection.count >= 2
        case .editing:
            return true  // Always allow — 0 or 1 selected will dissolve/remove
        case .none:
            return false
        }
    }

    /// Diffs the pending selection against the superset's existing membership
    /// (for `.editing`) or validates a brand-new selection (for `.creating`),
    /// returning the minimal decision the caller should apply.
    static func decideEdit(
        _ mode: SupersetEditMode?,
        selection: Set<UUID>,
        in routine: Routine
    ) -> SupersetEditDecision {
        let selectedExercises = routine.routineExercisesList
            .filter { selection.contains($0.id) }
            .sorted { $0.order < $1.order }

        switch mode {
        case .editing(let supersetId):
            if selectedExercises.count < 2 {
                // Dissolve the entire superset (0 or 1 remaining)
                return .dissolve(supersetId: supersetId)
            }
            let currentMembers = Set(routine.routineExercisesList
                .filter { $0.supersetId == supersetId }.map(\.id))
            let toAdd = selection.subtracting(currentMembers)
            let toRemove = currentMembers.subtracting(selection)
            return .modify(supersetId: supersetId, toAdd: toAdd, toRemove: toRemove)
        case .creating:
            guard selectedExercises.count >= 2 else { return .none }
            return .create(exercises: selectedExercises)
        case .none:
            return .none
        }
    }
}
