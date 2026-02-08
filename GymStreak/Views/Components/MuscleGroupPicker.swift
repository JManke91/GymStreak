import SwiftUI

/// A multi-select picker for muscle groups
struct MuscleGroupPicker: View {
    @Binding var selectedMuscleGroups: [String]
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack {
                Text("exercises.muscle_groups".localized)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedMuscleGroups.isEmpty {
                    Text("muscle_picker.select".localized)
                        .foregroundStyle(.secondary)
                } else {
                    Text(MuscleGroups.displayString(for: selectedMuscleGroups))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showingPicker) {
            MuscleGroupSelectionSheet(selectedMuscleGroups: $selectedMuscleGroups)
        }
    }
}

/// Sheet view for selecting multiple muscle groups
struct MuscleGroupSelectionSheet: View {
    @Binding var selectedMuscleGroups: [String]
    @Environment(\.dismiss) private var dismiss

    // Grouped muscle groups for better organization
    // Keys are localization keys, groups are internal English keys
    private let muscleGroupCategories: [(titleKey: String, groups: [String])] = [
        ("muscle_category.arms", ["Biceps", "Triceps", "Forearms"]),
        ("muscle_category.chest", ["Chest", "Upper Chest"]),
        ("muscle_category.back", ["Upper Back", "Lats", "Lower Back"]),
        ("muscle_category.shoulders", ["Shoulders", "Front Delts", "Side Delts", "Rear Delts"]),
        ("muscle_category.core", ["Abs", "Obliques"]),
        ("muscle_category.legs", ["Quadriceps", "Hamstrings", "Glutes", "Calves", "Hip Flexors"])
    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(muscleGroupCategories, id: \.titleKey) { category in
                    Section(category.titleKey.localized) {
                        ForEach(category.groups, id: \.self) { muscleGroup in
                            MuscleGroupRow(
                                muscleGroup: muscleGroup,
                                isSelected: selectedMuscleGroups.contains(muscleGroup),
                                onToggle: { toggleMuscleGroup(muscleGroup) }
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("muscle_picker.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done".localized) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleMuscleGroup(_ muscleGroup: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let index = selectedMuscleGroups.firstIndex(of: muscleGroup) {
                selectedMuscleGroups.remove(at: index)
            } else {
                selectedMuscleGroups.append(muscleGroup)
            }
        }
    }
}

/// Row view for a single muscle group selection
private struct MuscleGroupRow: View {
    let muscleGroup: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                MuscleGroupAbbreviationBadge(
                    muscleGroups: [muscleGroup],
                    isActive: isSelected,
                    size: .small
                )

                Text(MuscleGroups.displayName(for: muscleGroup))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selected: [String] = ["Chest", "Triceps"]

        var body: some View {
            Form {
                MuscleGroupPicker(selectedMuscleGroups: $selected)
            }
        }
    }

    return PreviewWrapper()
}
