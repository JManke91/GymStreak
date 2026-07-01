import SwiftUI
import SwiftData

/// Exercise picker for adding an alternative to a routine exercise.
/// Excludes the primary exercise itself and any already-added alternatives,
/// and surfaces exercises that share a muscle group with the primary first.
struct AddAlternativeView: View {
    let routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""

    /// IDs that cannot be chosen: the primary exercise and existing alternatives.
    private var excludedExerciseIds: Set<UUID> {
        var ids = Set(routineExercise.alternativesList.compactMap { $0.exercise?.id })
        if let primaryId = routineExercise.exercise?.id {
            ids.insert(primaryId)
        }
        return ids
    }

    private var primaryMuscleGroups: Set<String> {
        Set(routineExercise.exercise?.muscleGroups ?? [])
    }

    private var filteredExercises: [Exercise] {
        let available = exercises.filter { !excludedExerciseIds.contains($0.id) }
        let searched: [Exercise]
        if searchText.isEmpty {
            searched = available
        } else {
            searched = available.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText) ||
                exercise.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        // Same-muscle-group exercises first, then alphabetical within each group.
        return searched.sorted { lhs, rhs in
            let lhsMatch = !primaryMuscleGroups.isDisjoint(with: lhs.muscleGroups)
            let rhsMatch = !primaryMuscleGroups.isDisjoint(with: rhs.muscleGroups)
            if lhsMatch != rhsMatch { return lhsMatch }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredExercises) { exercise in
                    Button {
                        viewModel.addAlternative(exercise, to: routineExercise)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            MuscleGroupAbbreviationBadge(
                                muscleGroups: exercise.muscleGroups,
                                isActive: true
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: exercise.equipmentType.icon)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityLabel("alternatives.add_accessibility".localized(exercise.name))
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if filteredExercises.isEmpty {
                    ContentUnavailableView(
                        "alternatives.picker.empty.title".localized,
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("alternatives.picker.empty.message".localized)
                    )
                }
            }
            .navigationTitle("alternatives.picker.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "exercise_picker.search".localized)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: fetchExercises)
    }

    private func fetchExercises() {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name, order: .forward)])
        do {
            exercises = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching exercises: \(error)")
        }
    }
}
