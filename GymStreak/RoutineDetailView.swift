import SwiftUI

struct RoutineDetailView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @State private var showingAddExercise = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            Section("Routine Info") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(routine.name)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Exercises")
                    Spacer()
                    Text("\(routine.routineExercises.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Created")
                    Spacer()
                    Text(routine.createdAt, style: .date)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Exercises") {
                if routine.routineExercises.isEmpty {
                    Text("No exercises added yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(routine.routineExercises.sorted(by: { $0.order < $1.order })) { routineExercise in
                        NavigationLink(destination: RoutineExerciseDetailView(routineExercise: routineExercise, viewModel: viewModel)) {
                            RoutineExerciseRowView(routineExercise: routineExercise)
                        }
                    }
                    .onDelete(perform: deleteRoutineExercises)
                }
                
                Button("Add Exercise") {
                    showingAddExercise = true
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Routine", action: {})
                    Button("Delete Routine", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToRoutineView(routine: routine, viewModel: viewModel)
        }
        .alert("Delete Routine", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.deleteRoutine(routine)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(routine.name)'? This action cannot be undone.")
        }
    }
    
    private func deleteRoutineExercises(offsets: IndexSet) {
        for index in offsets {
            let routineExercise = routine.routineExercises.sorted(by: { $0.order < $1.order })[index]
            viewModel.removeRoutineExercise(routineExercise, from: routine)
        }
    }
}

struct RoutineExerciseRowView: View {
    let routineExercise: RoutineExercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let exercise = routineExercise.exercise {
                Text(exercise.name)
                    .font(.headline)
                Text("\(routineExercise.sets.count) sets")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Unknown Exercise")
                    .font(.headline)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text("RoutineDetailView Preview")
}
