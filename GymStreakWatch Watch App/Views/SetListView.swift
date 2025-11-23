import SwiftUI

struct SetListView: View {
    let exercise: ActiveWorkoutExercise
    let progress: Double
    let completedSets: Int
    let totalSets: Int

    @EnvironmentObject var viewModel: WatchWorkoutViewModel
    @State private var editingSet: ActiveWorkoutSet?
    @State private var showingEditor = false
    @State private var showingRestTimerEditor = false

    var body: some View {
        List {
            // Progress header section
            Section {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ProgressRing(progress: progress)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(completedSets)/\(totalSets) sets")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)

                            // Rest timer indicator
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.caption2)
                                Text(formattedRestTime)
                                    .font(.caption.monospacedDigit())
                            }
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Edit button
                        Button {
                            showingRestTimerEditor = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rest timer: \(formattedRestTime)")
                        .accessibilityHint("Double tap to edit rest duration for all sets")
                        .accessibilityAddTraits(.isButton)
                    }

                    // Compact timer integration
                    if viewModel.isResting && viewModel.isRestTimerMinimized {
                        CompactRestTimer(
                            timeRemaining: viewModel.restTimeRemaining,
                            totalDuration: viewModel.restDuration,
                            formattedTime: viewModel.formattedRestTime,
                            onSkip: viewModel.skipRest,
                            onExpand: viewModel.expandRestTimer
                        )
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Sets section
            Section {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(
                        set: set,
                        setNumber: index + 1,
                        isCurrent: index == viewModel.currentSetIndex &&
                                   exercise.id == viewModel.currentExercise?.id,
                        onToggle: {
                            toggleSetCompletion(set)
                        },
                        onEdit: {
                            editingSet = set
                            showingEditor = true
                        }
                    )
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleSetCompletion(set)
                        } label: {
                            Label(
                                set.isCompleted ? "Undo" : "Done",
                                systemImage: set.isCompleted ? "arrow.uturn.backward" : "checkmark"
                            )
                        }
                        .tint(set.isCompleted ? .orange : .green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            editingSet = set
                            showingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(setAccessibilityLabel(for: set, number: index + 1))
                    .accessibilityHint("Double tap to mark \(set.isCompleted ? "incomplete" : "complete"). Swipe up or down for actions")
                    .accessibilityAddTraits(set.isCompleted ? [.isSelected] : [])
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRestTimerMinimized)
        .sheet(isPresented: $showingEditor) {
            if let set = editingSet {
                SetEditorSheet(
                    set: set,
                    exerciseId: exercise.id,
                    onSave: { updatedSet in
                        viewModel.updateSet(updatedSet, in: exercise.id)
                        showingEditor = false
                    },
                    onCancel: {
                        showingEditor = false
                    }
                )
                .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showingRestTimerEditor) {
            RestTimerEditorSheet(
                currentRestTime: exercise.sets.first?.restTime ?? 0,
                onSave: { newRestTime in
                    viewModel.updateRestTime(for: exercise.id, newRestTime: newRestTime)
                    showingRestTimerEditor = false
                },
                onCancel: {
                    showingRestTimerEditor = false
                }
            )
        }
    }

    // MARK: - Actions

    private func toggleSetCompletion(_ set: ActiveWorkoutSet) {
        viewModel.toggleSetCompletion(set.id, in: exercise.id)
    }

    private var formattedRestTime: String {
        let restTime = exercise.sets.first?.restTime ?? 0
        let minutes = Int(restTime) / 60
        let seconds = Int(restTime) % 60

        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            return "\(seconds)s"
        }
    }

    private func setAccessibilityLabel(for set: ActiveWorkoutSet, number: Int) -> String {
        var label = "Set \(number), \(Int(set.actualWeight)) pounds, \(set.actualReps) reps"

        if set.isCompleted {
            label += ", completed"
        }

        if set.wasModified {
            label += ", modified from template"
        }

        return label
    }
}

// MARK: - Set Row

struct SetRow: View {
    let set: ActiveWorkoutSet
    let setNumber: Int
    let isCurrent: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Status icon
                statusIcon
                    .font(.title3)
                    .frame(width: 24)

                // Set info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set \(setNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("\(Int(set.actualWeight))")
                            .font(.body.monospacedDigit())
                            .fontWeight(.semibold)

                        Text("×")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(set.actualReps)")
                            .font(.body.monospacedDigit())
                            .fontWeight(.semibold)

                        Text("lbs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .strikethrough(set.isCompleted, color: .secondary)
                    .foregroundStyle(set.isCompleted ? .secondary : .primary)
                }

                Spacer()

                // Modified indicator
                if set.wasModified {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isCurrent ? Color.blue.opacity(0.15) : Color.clear
        )
    }

    private var statusIcon: some View {
        Group {
            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isCurrent {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SetListView(
            exercise: ActiveWorkoutExercise(
                id: UUID(),
                name: "Bench Press",
                muscleGroup: "Chest",
                sets: [
                    ActiveWorkoutSet(
                        id: UUID(),
                        plannedReps: 10,
                        actualReps: 10,
                        plannedWeight: 135,
                        actualWeight: 135,
                        restTime: 90,
                        isCompleted: true,
                        completedAt: Date(),
                        order: 0
                    ),
                    ActiveWorkoutSet(
                        id: UUID(),
                        plannedReps: 10,
                        actualReps: 10,
                        plannedWeight: 135,
                        actualWeight: 140,
                        restTime: 90,
                        isCompleted: true,
                        completedAt: Date(),
                        order: 1
                    ),
                    ActiveWorkoutSet(
                        id: UUID(),
                        plannedReps: 10,
                        actualReps: 10,
                        plannedWeight: 135,
                        actualWeight: 135,
                        restTime: 90,
                        isCompleted: false,
                        completedAt: nil,
                        order: 2
                    ),
                    ActiveWorkoutSet(
                        id: UUID(),
                        plannedReps: 10,
                        actualReps: 10,
                        plannedWeight: 135,
                        actualWeight: 135,
                        restTime: 90,
                        isCompleted: false,
                        completedAt: nil,
                        order: 3
                    )
                ],
                order: 0
            ),
            progress: 0.5,
            completedSets: 2,
            totalSets: 4
        )
        .environmentObject(WatchWorkoutViewModel(
            healthKitManager: WatchHealthKitManager(),
            connectivityManager: WatchConnectivityManager.shared
        ))
    }
}
