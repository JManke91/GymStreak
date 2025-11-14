import SwiftUI

struct EditSetView: View {
    let set: ExerciseSet
    let routineExercise: RoutineExercise
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var reps: Int
    @State private var weight: Double
    @State private var restTime: TimeInterval
    
    init(set: ExerciseSet, routineExercise: RoutineExercise, viewModel: RoutinesViewModel) {
        self.set = set
        self.routineExercise = routineExercise
        self.viewModel = viewModel
        self._reps = State(initialValue: set.reps)
        self._weight = State(initialValue: set.weight)
        self._restTime = State(initialValue: set.restTime)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Set Details") {
                    Stepper("Reps: \(reps)", value: $reps, in: 1...100)
                    
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("0.0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Rest Time")
                        Spacer()
                        Text("\(Int(restTime))s")
                    }
                    Slider(value: $restTime, in: 0...300, step: 30)
                        .onChange(of: restTime) { _, newValue in
                            let rounded = round(newValue / 30) * 30
                            if rounded != restTime {
                                restTime = rounded
                            }
                        }
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSet()
                    }
                }
            }
        }
    }
    
    private func saveSet() {
        set.reps = reps
        set.weight = weight
        set.restTime = restTime
        
        if let routine = routineExercise.routine {
            viewModel.updateRoutine(routine)
        }
        
        dismiss()
    }
}

#Preview {
    Text("EditSetView Preview")
}
