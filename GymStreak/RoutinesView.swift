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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("routines.add".localized) {
                        viewModel.showingAddRoutine = true
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
        }
        .onAppear {
            viewModel.fetchRoutines()
        }
    }

    private func deleteRoutines(offsets: IndexSet) {
        for index in offsets {
            viewModel.deleteRoutine(viewModel.routines[index])
        }
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
