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
                        .tint(Color.appAccent)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("exercises.add".localized) {
                        viewModel.showingAddExercise = true
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingAddExercise) {
                AddExerciseView(viewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.fetchExercises()
        }
    }

    private func deleteExercises(offsets: IndexSet) {
        for index in offsets {
            viewModel.deleteExercise(viewModel.exercises[index])
        }
    }
}

struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.headline)
            Text(MuscleGroups.displayString(for: exercise.muscleGroups))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text("ExercisesView Preview")
}
