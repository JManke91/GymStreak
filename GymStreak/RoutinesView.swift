import SwiftUI
import SwiftData

struct RoutinesView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RoutinesViewInternal(modelContext: modelContext)
    }
}

private struct RoutinesViewInternal: View {
    @StateObject private var viewModel: RoutinesViewModel
    @StateObject private var exercisesViewModel: ExercisesViewModel
    @StateObject private var workoutViewModel: WorkoutViewModel
    @State private var routinePendingDeletion: Routine?
    @State private var showingDeleteAlert = false

    init(modelContext: ModelContext) {
        self._viewModel = StateObject(wrappedValue: RoutinesViewModel(modelContext: modelContext))
        self._exercisesViewModel = StateObject(wrappedValue: ExercisesViewModel(modelContext: modelContext))
        self._workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.routines.isEmpty {
                    ContentUnavailableView {
                        Label("routines.empty.title".localized, systemImage: "list.bullet.clipboard")
                    } description: {
                        Text("routines.empty.description".localized)
                    } actions: {
                        Button("routines.add".localized) {
                            viewModel.showingAddRoutine = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.tint)
                    }
                } else {
                    List {
                        ForEach(viewModel.routines) { routine in
                            NavigationLink(destination: RoutineDetailView(routine: routine, viewModel: viewModel, exercisesViewModel: exercisesViewModel, workoutViewModel: workoutViewModel)) {
                                RoutineRowView(routine: routine)
                            }
                        }
                        .onDelete(perform: deleteRoutines)
                    }
                }
            }
            .navigationTitle("routines.title".localized)
            .toolbar {
                if !viewModel.routines.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            viewModel.showingAddRoutine = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("routines.add".localized)
                    }
                }
            }
            .fullScreenCover(isPresented: $viewModel.showingAddRoutine) {
                NavigationStack {
                    CreateRoutineView(
                        routinesViewModel: viewModel,
                        exercisesViewModel: exercisesViewModel
                    )
                }
            }
            .alert("routine.delete".localized, isPresented: $showingDeleteAlert) {
                Button("action.delete".localized, role: .destructive) {
                    if let routine = routinePendingDeletion {
                        viewModel.deleteRoutine(routine)
                        routinePendingDeletion = nil
                    }
                }
                Button("action.cancel".localized, role: .cancel) {
                    routinePendingDeletion = nil
                }
            } message: {
                Text("routine.delete.confirm".localized)
            }
        }
        .onAppear {
            viewModel.fetchRoutines()
        }
    }

    private func deleteRoutines(offsets: IndexSet) {
        guard let index = offsets.first else { return }
        routinePendingDeletion = viewModel.routines[index]
        showingDeleteAlert = true
    }
}

struct RoutineRowView: View {
    let routine: Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routine.name)
                .font(.headline)
            Text("routines.exercise_count".localized(routine.routineExercisesList.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoutinesView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self], inMemory: true)
}
