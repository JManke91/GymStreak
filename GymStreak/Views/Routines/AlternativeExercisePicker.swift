import SwiftUI
import SwiftData

/// Reusable exercise picker content for choosing an alternative exercise.
/// Works both pushed onto a NavigationStack (pre-save configure flows) and
/// wrapped in its own stack inside a sheet (routine detail edit mode).
/// Excludes the primary exercise and already-added alternatives, and surfaces
/// exercises that share a muscle group with the primary first.
struct AlternativeExercisePicker: View {
    let primaryExercise: Exercise?
    let excludedExerciseIds: Set<UUID>
    let onSelect: (Exercise) -> Void
    @Environment(\.modelContext) private var modelContext

    @State private var exercises: [Exercise] = []
    @State private var searchText = ""

    private var primaryMuscleGroups: Set<String> {
        Set(primaryExercise?.muscleGroups ?? [])
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
        List {
            ForEach(filteredExercises) { exercise in
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSelect(exercise)
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
