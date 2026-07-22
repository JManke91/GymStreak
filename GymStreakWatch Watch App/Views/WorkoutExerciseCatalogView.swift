import SwiftUI

struct WorkoutExerciseCatalogView: View {
    @EnvironmentObject private var catalogStore: ExerciseCatalogStore
    @EnvironmentObject private var workoutViewModel: WatchWorkoutViewModel

    let onSelect: (WatchExerciseCatalogItem) -> Void

    @State private var searchText = ""

    private var displayState: WatchExerciseCatalogDisplayState {
        WatchWorkoutStructuralReducer.catalogueState(
            hasReceivedCatalog: catalogStore.hasReceivedCatalog,
            items: catalogStore.items
        )
    }

    private var filteredItems: [WatchExerciseCatalogItem] {
        guard !searchText.isEmpty else { return catalogStore.items }
        return catalogStore.items.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.muscleGroups.contains { $0.localizedStandardContains(searchText) }
                || $0.equipmentTypeRaw.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        Group {
            switch displayState {
            case .neverSynced:
                unavailableState(
                    icon: "iphone.and.arrow.forward",
                    title: "Exercise library not synced",
                    message: "Open GymStreak on your iPhone to sync your exercise library."
                )

            case .empty:
                unavailableState(
                    icon: "tray",
                    title: "No exercises on iPhone",
                    message: "Add an exercise in the iPhone app, then sync again."
                )

            case .populated:
                List(filteredItems, id: \.id) { item in
                    let isActive = WatchWorkoutStructuralReducer.isAlreadyActive(
                        item,
                        in: workoutViewModel.exercises
                    )
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(metadata(for: item))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(OnyxWatch.Colors.success)
                                    .accessibilityLabel("Already in workout")
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(isActive)
                    .accessibilityHint(isActive ? "Remove it from the workout before adding it again" : "Configure sets for this exercise")
                }
                .listStyle(.carousel)
                .searchable(text: $searchText, prompt: "Search exercises")
            }
        }
        .navigationTitle("Add Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unavailableState(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey
    ) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(OnyxWatch.Colors.tint)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)
        }
    }

    private func metadata(for item: WatchExerciseCatalogItem) -> String {
        let muscle = item.muscleGroups.first ?? String(localized: "General")
        let equipment = item.equipmentTypeRaw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return "\(muscle) · \(equipment)"
    }
}
