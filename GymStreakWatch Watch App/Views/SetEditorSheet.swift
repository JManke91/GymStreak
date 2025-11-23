import SwiftUI

struct SetEditorSheet: View {
    let set: ActiveWorkoutSet
    let exerciseId: UUID
    let onSave: (ActiveWorkoutSet) -> Void
    let onCancel: () -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var focusedField: Field = .weight
    @Environment(\.dismiss) private var dismiss

    enum Field {
        case weight
        case reps
    }

    init(set: ActiveWorkoutSet, exerciseId: UUID, onSave: @escaping (ActiveWorkoutSet) -> Void, onCancel: @escaping () -> Void) {
        self.set = set
        self.exerciseId = exerciseId
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state from current set values
        _weight = State(initialValue: set.actualWeight)
        _reps = State(initialValue: set.actualReps)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Edit Set")
                    .font(.headline)
                    .padding(.top, 8)

                // Weight picker
                VStack(spacing: 4) {
                    Text("WEIGHT")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        focusedField = .weight
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(Int(weight))")
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()

                            Text("lbs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        .foregroundStyle(focusedField == .weight ? .blue : .primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(focusedField == .weight ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(focusedField == .weight ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(focusedField == .weight)
                    .digitalCrownRotation(
                        $weight,
                        from: 0,
                        through: 999,
                        by: 5,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .onChange(of: weight) { oldValue, newValue in
                        if focusedField == .weight {
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                }

                // Reps picker
                VStack(spacing: 4) {
                    Text("REPS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        focusedField = .reps
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(reps)")
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()

                            Text("reps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        .foregroundStyle(focusedField == .reps ? .blue : .primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(focusedField == .reps ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(focusedField == .reps ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(focusedField == .reps)
                    .digitalCrownRotation(
                        Binding(
                            get: { Double(reps) },
                            set: { reps = Int($0) }
                        ),
                        from: 0,
                        through: 100,
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .onChange(of: reps) { oldValue, newValue in
                        if focusedField == .reps {
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                }

                Spacer()

                // Save button
                Button {
                    saveChanges()
                } label: {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        WKInterfaceDevice.current().play(.click)
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func saveChanges() {
        var updatedSet = set
        updatedSet.actualWeight = weight
        updatedSet.actualReps = reps

        WKInterfaceDevice.current().play(.success)
        onSave(updatedSet)
        dismiss()
    }
}

#Preview {
    SetEditorSheet(
        set: ActiveWorkoutSet(
            id: UUID(),
            plannedReps: 10,
            actualReps: 10,
            plannedWeight: 135,
            actualWeight: 135,
            restTime: 90,
            isCompleted: false,
            completedAt: nil,
            order: 0
        ),
        exerciseId: UUID(),
        onSave: { _ in },
        onCancel: { }
    )
}
