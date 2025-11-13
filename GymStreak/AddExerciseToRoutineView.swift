import SwiftUI

struct AddExerciseToRoutineView: View {
    let routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedExercise: Exercise?
    @State private var sets: [ExerciseSet] = []
    @State private var globalRestTime: TimeInterval = 60.0
    @State private var editingSetIndex: Int?
    @State private var editingReps = 10
    @State private var editingWeight = 0.0
    @State private var isDuplicating = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Exercise Selection") {
                    NavigationLink(destination: ExercisePickerView(selectedExercise: $selectedExercise)) {
                        HStack {
                            Image(systemName: "dumbbell.fill")
                                .foregroundColor(.blue)
                            Text("Choose Exercise")
                                .foregroundColor(.primary)
                            Spacer()
                            if let exercise = selectedExercise {
                                Text(exercise.name)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                if let exercise = selectedExercise {
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
                    }
                    
                    Section("Sets") {
                        ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                            VStack(alignment: .leading, spacing: 0) {
                                // Display set with tap to edit
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        // Collapse current set if different from clicked set
                                        if editingSetIndex == index {
                                            editingSetIndex = nil
                                        } else {
                                            editingSetIndex = index
                                            editingReps = set.reps
                                            editingWeight = set.weight
                                        }
                                    }
                                }) {
                                    HStack {
                                        Text("Set \(index + 1)")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("\(set.reps) reps • \(set.weight, specifier: "%.1f") kg")
                                            .foregroundColor(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .rotationEffect(.degrees(editingSetIndex == index ? 90 : 0))
                                            .animation(.easeInOut(duration: 0.2), value: editingSetIndex == index)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                // Inline edit form for this set
                                if editingSetIndex == index {
                                    VStack(spacing: 12) {
                                        HStack {
                                            Text("Reps:")
                                            Spacer()
                                            Stepper("\(editingReps)", value: $editingReps, in: 1...100)
                                                .onChange(of: editingReps) { _, newValue in
                                                    updateSet(at: index)
                                                }
                                        }
                                        
                                        HStack {
                                            Text("Weight (kg):")
                                            Spacer()
                                            TextField("0.0", value: $editingWeight, format: .number)
                                                .keyboardType(.decimalPad)
                                                .multilineTextAlignment(.trailing)
                                                .frame(width: 80)
                                                .onChange(of: editingWeight) { _, newValue in
                                                    updateSet(at: index)
                                                }
                                        }
                                    }
                                    .padding(.top, 8)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                                    ))
                                }
                            }
                        }
                        .onDelete(perform: deleteSets)
                        
                        VStack(spacing: 4) {
                            Button(action: {
                                print("DEBUG: Add Set button tapped!")
                                addNewSet()
                            }) {
                                Text("Add Set")
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if !sets.isEmpty {
                                Button(action: {
                                    print("DEBUG: Duplicate button tapped!")
                                    duplicateLastSet()
                                }) {
                                    Text("Duplicate Last Set")
                                        .foregroundColor(.green)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isDuplicating)
                            }
                        }
                    }
                    
                    Section("Rest Timer") {
                        HStack {
                            Text("Rest Time Between Sets")
                            Spacer()
                            Text("\(Int(globalRestTime))s")
                        }
                        Slider(value: $globalRestTime, in: 0...300, step: 5)
                    }
                }
            }
            .navigationTitle("Add Exercise to Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveExerciseToRoutine()
                    }
                    .disabled(selectedExercise == nil || sets.isEmpty)
                }
            }
        }
    }
    
    private func addNewSet() {
        print("DEBUG: addNewSet() called - current sets count: \(sets.count)")
        let newSet = ExerciseSet(reps: 10, weight: 0.0, restTime: globalRestTime)
        sets.append(newSet)
        print("DEBUG: addNewSet() - added new set, count now: \(sets.count)")
        
        // Auto-open the newly added set for editing with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetIndex = sets.count - 1
            editingReps = newSet.reps
            editingWeight = newSet.weight
        }
    }
    
    private func duplicateLastSet() {
        print("DEBUG: duplicateLastSet() function called")
        print("DEBUG: Current sets count: \(sets.count)")
        print("DEBUG: Current editingSetIndex: \(String(describing: editingSetIndex))")
        
        guard let lastSet = sets.last else { 
            print("DEBUG: No sets to duplicate")
            return 
        }
        
        // Determine the values to use for duplication
        let repsToUse: Int
        let weightToUse: Double
        
        // If the last set is currently being edited, use the editing values
        if let editingIndex = editingSetIndex, editingIndex == sets.count - 1 {
            print("DEBUG: Last set is being edited, using current editing values")
            repsToUse = editingReps
            weightToUse = editingWeight
            print("DEBUG: Using editing values - reps: \(repsToUse), weight: \(weightToUse)")
        } else {
            print("DEBUG: Last set not being edited, using saved values")
            repsToUse = lastSet.reps
            weightToUse = lastSet.weight
            print("DEBUG: Using saved values - reps: \(repsToUse), weight: \(weightToUse)")
        }
        
        // Create ONE duplicate set
        let newSet = ExerciseSet(reps: repsToUse, weight: weightToUse, restTime: globalRestTime)
        print("DEBUG: Created new set with reps: \(newSet.reps), weight: \(newSet.weight)")
        
        sets.append(newSet)
        print("DEBUG: Appended set. New count: \(sets.count)")
        
        // Open the new set for editing
        withAnimation(.easeInOut(duration: 0.3)) {
            editingSetIndex = sets.count - 1
            editingReps = newSet.reps
            editingWeight = newSet.weight
        }
        
        print("DEBUG: Set editing values - reps: \(editingReps), weight: \(editingWeight)")
        print("DEBUG: Function complete")
    }
    
    private func updateSet(at index: Int) {
        guard index < sets.count else { return }
        sets[index].reps = editingReps
        sets[index].weight = editingWeight
    }
    
    
    private func deleteSets(offsets: IndexSet) {
        sets.remove(atOffsets: offsets)
        // Reset editing if the edited set was deleted
        if let editingIndex = editingSetIndex, editingIndex >= sets.count {
            editingSetIndex = nil
        }
    }
    
    private func saveExerciseToRoutine() {
        guard let exercise = selectedExercise else { return }
        
        let routineExercise = RoutineExercise(exercise: exercise, order: routine.routineExercises.count)
        routineExercise.routine = routine
        
        // Apply the global rest time to all sets
        for set in sets {
            set.restTime = globalRestTime
            set.routineExercise = routineExercise
            routineExercise.sets.append(set)
        }
        
        routine.routineExercises.append(routineExercise)
        viewModel.updateRoutine(routine)
        
        dismiss()
    }
}

#Preview {
    Text("AddExerciseToRoutineView Preview")
}
