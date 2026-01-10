import SwiftUI
import SwiftData

struct ExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ExercisesViewModel
    
    init() {
        self._viewModel = StateObject(wrappedValue: ExercisesViewModel(modelContext: ModelContext(try! ModelContainer(for: Exercise.self))))
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
            viewModel.updateModelContext(modelContext)
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
            HStack {
                Text(exercise.muscleGroup)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !exercise.exerciseDescription.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(exercise.exerciseDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text("ExercisesView Preview")
}
