import SwiftUI

struct RoutineExerciseDetailView: View {
    let routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    @State private var showingEditExercise = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            Section("Exercise Info") {
                if let exercise = routineExercise.exercise {
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
                } else {
                    Text("Exercise not found")
                        .foregroundColor(.red)
                }
                
                HStack {
                    Text("Sets")
                    Spacer()
                    Text("\(routineExercise.sets.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Sets") {
                ForEach(routineExercise.sets) { set in
                    SetRowView(set: set)
                }
                .onDelete(perform: deleteSets)
                
                Button("Add Set") {
                    viewModel.addSet(to: routineExercise)
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle(routineExercise.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Exercise", action: {})
                    Button("Delete Exercise", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Exercise", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let routine = routineExercise.routine {
                    viewModel.removeRoutineExercise(routineExercise, from: routine)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this exercise from the routine? This action cannot be undone.")
        }
    }
    
    private func deleteSets(offsets: IndexSet) {
        for index in offsets {
            viewModel.removeSet(routineExercise.sets[index], from: routineExercise)
        }
    }
}

struct SetRowView: View {
    let set: ExerciseSet
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set \(set.id.uuidString.prefix(8))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("\(set.reps) reps")
                    Text("•")
                    Text("\(set.weight, specifier: "%.1f") kg")
                    Text("•")
                    Text("\(Int(set.restTime))s rest")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    Text("RoutineExerciseDetailView Preview")
}
