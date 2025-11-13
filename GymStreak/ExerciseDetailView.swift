import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @ObservedObject var viewModel: ExercisesViewModel
    @State private var showingEditExercise = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            Section("Exercise Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(exercise.name)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Muscle Group")
                    Spacer()
                    Text(exercise.muscleGroup)
                        .foregroundColor(.secondary)
                }
                
                if !exercise.exerciseDescription.isEmpty {
                    HStack {
                        Text("Description")
                        Spacer()
                        Text(exercise.exerciseDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                HStack {
                    Text("Created")
                    Spacer()
                    Text(exercise.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Last Updated")
                    Spacer()
                    Text(exercise.updatedAt, style: .date)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Exercise") {
                        showingEditExercise = true
                    }
                    Button("Delete Exercise", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditExercise) {
            EditExerciseView(exercise: exercise, viewModel: viewModel)
        }
        .alert("Delete Exercise", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteExercise(exercise)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(exercise.name)'? This action cannot be undone.")
        }
    }
}

#Preview {
    Text("ExerciseDetailView Preview")
}
