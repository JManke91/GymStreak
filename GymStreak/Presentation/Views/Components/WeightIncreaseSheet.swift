//
//  WeightIncreaseSheet.swift
//  GymStreak
//

import SwiftUI

struct WeightIncreaseSheet: View {
    let currentWeight: Double
    let currentReps: Int
    let setCount: Int
    let targetMin: Int
    let isAssistance: Bool
    let onApply: (Double) -> Void
    let onCancel: () -> Void

    @State private var selectedIncrement: Double = ProgressiveOverloadIncrement.default

    /// One shared list with the watch picker (`Domain/Services/ProgressiveOverloadService`),
    /// so the two platforms cannot offer different steps again.
    private let increments: [Double] = ProgressiveOverloadIncrement.options

    /// Routine-editor surface: current values come from the template sets.
    init(routineExercise: RoutineExercise, onApply: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.currentWeight = routineExercise.setsList.first?.weight ?? 0
        self.currentReps = routineExercise.setsList.first?.reps ?? 0
        self.setCount = routineExercise.setsList.count
        self.targetMin = routineExercise.targetRepMin ?? 0
        self.isAssistance = routineExercise.exercise?.loadBehavior.isCounterweightAssistance == true
        self.onApply = onApply
        self.onCancel = onCancel
    }

    /// Workout surfaces (active workout, completion screen): current values are
    /// what the user actually lifted — correct for swapped exercises too, whose
    /// performed weights never live on the primary template sets.
    init(workoutExercise: WorkoutExercise, onApply: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        let firstSet = workoutExercise.setsList.sorted { $0.order < $1.order }.first
        self.currentWeight = firstSet?.actualWeight ?? 0
        self.currentReps = firstSet?.actualReps ?? 0
        self.setCount = workoutExercise.setsList.count
        self.targetMin = workoutExercise.targetRepMin ?? 0
        self.isAssistance = workoutExercise.loadBehavior.isCounterweightAssistance
        self.onApply = onApply
        self.onCancel = onCancel
    }

    private var resultingWeight: Double {
        isAssistance ? max(0, currentWeight - selectedIncrement) : currentWeight + selectedIncrement
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Current state
                Text("rep_range.current_state".localized(
                    String(format: "%.1f", currentWeight),
                    currentReps,
                    setCount
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                // Increment options
                VStack(spacing: 8) {
                    ForEach(increments, id: \.self) { increment in
                        Button {
                            selectedIncrement = increment
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Image(systemName: selectedIncrement == increment ? "circle.inset.filled" : "circle")
                                    .foregroundStyle(selectedIncrement == increment ? .orange : .secondary)

                                // Two fraction digits, not `%.2g`: at two
                                // SIGNIFICANT digits a 1.25 kg step rendered as
                                // a misleading "1.2".
                                Text("\(isAssistance ? "−" : "+")\(increment.formatted(.number.precision(.fractionLength(0...2)))) kg")
                                    .font(.body.weight(.medium))

                                Spacer()

                                Text("\(String(format: "%.1f", isAssistance ? max(0, currentWeight - increment) : currentWeight + increment)) kg")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedIncrement == increment
                                        ? Color.orange.opacity(0.1)
                                        : DesignSystem.Colors.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(selectedIncrement == increment
                                        ? Color.orange.opacity(0.4)
                                        : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Preview
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.orange)
                    Text(
                        isAssistance
                            ? String(format: "exercise.assistance.value".localized, String(format: "%.1f", resultingWeight))
                            : "rep_range.new_state".localized(String(format: "%.1f", resultingWeight), targetMin)
                    )
                    .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                )

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onApply(selectedIncrement)
                    } label: {
                        Text("rep_range.apply".localized)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textOnTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCancel()
                    } label: {
                        Text("action.cancel".localized)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle("rep_range.increase_weight".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
    }
}
