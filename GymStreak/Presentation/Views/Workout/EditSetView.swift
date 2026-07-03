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
                Section("edit_set.details".localized) {
                    HorizontalStepper(
                        title: "set.reps_label".localized,
                        value: $reps,
                        range: 1...100,
                        step: 1
                    )

                    WeightInput(
                        title: "set.weight_label".localized,
                        weight: $weight,
                        increment: 0.25
                    )

                    VStack(spacing: 8) {
                        HStack {
                            Text("edit_set.rest_time".localized)
                                .font(.subheadline)
                            Spacer()
                            Text(TimeFormatting.formatRestTime(restTime))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
            }
            .navigationTitle("edit_set.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("action.save".localized) {
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
