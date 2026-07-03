import SwiftUI
import SwiftData

/// Sheet wrapper around AlternativeExercisePicker for adding an alternative
/// to an already-persisted routine exercise (routine detail edit mode).
struct AddAlternativeView: View {
    let routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    /// Called with the newly created alternative so the presenter can chain
    /// into its set editor after this sheet dismisses.
    var onAdded: ((RoutineExerciseAlternative) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// IDs that cannot be chosen: the primary exercise and existing alternatives.
    private var excludedExerciseIds: Set<UUID> {
        var ids = Set(routineExercise.alternativesList.compactMap { $0.exercise?.id })
        if let primaryId = routineExercise.exercise?.id {
            ids.insert(primaryId)
        }
        return ids
    }

    var body: some View {
        NavigationStack {
            AlternativeExercisePicker(
                primaryExercise: routineExercise.exercise,
                excludedExerciseIds: excludedExerciseIds,
                onSelect: { exercise in
                    let alternative = viewModel.addAlternative(exercise, to: routineExercise)
                    onAdded?(alternative)
                    dismiss()
                }
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
}
