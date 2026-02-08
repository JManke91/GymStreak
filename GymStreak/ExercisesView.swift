import SwiftUI
import SwiftData

struct ExercisesView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ExercisesViewInternal(modelContext: modelContext)
    }
}

private struct ExercisesViewInternal: View {
    @StateObject private var viewModel: ExercisesViewModel

    init(modelContext: ModelContext) {
        self._viewModel = StateObject(wrappedValue: ExercisesViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.exercises.isEmpty {
                    ContentUnavailableView {
                        Label("exercises.empty.title".localized, systemImage: "dumbbell")
                    } description: {
                        Text("exercises.empty.description".localized)
                    } actions: {
                        Button("exercises.add".localized) {
                            viewModel.showingAddExercise = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.tint)
                    }
                } else {
                    List {
                        ForEach(viewModel.exercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exercise: exercise, viewModel: viewModel)) {
                                ExerciseRowView(exercise: exercise)
                            }
                        }
                        .onDelete(perform: deleteExercises)
                    }
                }
            }
            .navigationTitle("exercises.title".localized)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Delete All", role: .destructive) {
                        viewModel.requestDeleteAllExercises()
                    }
                    .foregroundColor(.red)
                }
                #endif
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("exercises.add".localized) {
                        viewModel.showingAddExercise = true
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingAddExercise) {
                AddExerciseView(viewModel: viewModel)
            }
            .alert("exercises.delete.confirmation.title".localized, isPresented: $viewModel.showingDeleteConfirmation) {
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelDeleteExercise()
                }
                Button("exercises.delete.confirm".localized, role: .destructive) {
                    viewModel.confirmDeleteExercise()
                }
            } message: {
                let exerciseName = viewModel.exerciseToDelete?.name ?? ""
                if viewModel.routinesUsingExercise.isEmpty {
                    Text(String(format: "exercises.delete.confirmation.message_standalone".localized, exerciseName))
                } else {
                    let routineNames = viewModel.routinesUsingExercise.map(\.name).joined(separator: ", ")
                    Text(String(format: "exercises.delete.confirmation.message".localized, exerciseName, routineNames))
                }
            }
            .alert("exercises.deleteAll.confirmation.title".localized, isPresented: $viewModel.showingDeleteAllConfirmation) {
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelDeleteAllExercises()
                }
                Button("exercises.deleteAll.confirm".localized, role: .destructive) {
                    viewModel.confirmDeleteAllExercises()
                }
            } message: {
                Text("exercises.deleteAll.confirmation.message".localized)
            }
        }
        .onAppear {
            viewModel.fetchExercises()
        }
    }

    private func deleteExercises(offsets: IndexSet) {
        for index in offsets {
            viewModel.requestDeleteExercise(viewModel.exercises[index])
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.headline)
            HStack(spacing: 6) {
                Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: exercise.equipmentType.icon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text("ExercisesView Preview")
}
