//
//  WeightIncreaseSheet.swift
//  GymStreak
//

import SwiftUI

struct WeightIncreaseSheet: View {
    /// Canonical kilograms.
    let currentWeight: Double
    let currentReps: Int
    let setCount: Int
    let targetMin: Int
    let isAssistance: Bool
    /// Called with the increment in **canonical kilograms** — this sheet is the
    /// one place the user's pick is converted, and it happens once.
    let onApply: (Double) -> Void
    let onCancel: () -> Void

    @Environment(\.weightUnit) private var weightUnit

    /// The chosen step, in the unit the user reads. `nil` until the sheet has
    /// seen its unit — the grid is per-unit, so the default cannot be resolved
    /// at initialization, before the environment exists.
    @State private var selectedIncrement: Double?

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

    /// Workout surfaces (active workout, completion screen). `templateFirstSet`
    /// is what the apply actually raises — pass it (via
    /// `WorkoutViewModel.overloadTemplateFirstSet(for:)`) so the preview can't
    /// promise a different number than the confirmation announces when the user
    /// lifted more or less than planned. Falls back to the performed values
    /// when the template target can't be resolved — correct for swapped
    /// exercises too, whose performed weights never live on the primary
    /// template sets.
    init(
        workoutExercise: WorkoutExercise,
        templateFirstSet: (weight: Double, reps: Int)? = nil,
        onApply: @escaping (Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let firstSet = workoutExercise.setsList.sorted { $0.order < $1.order }.first
        self.currentWeight = templateFirstSet?.weight ?? firstSet?.actualWeight ?? 0
        self.currentReps = templateFirstSet?.reps ?? firstSet?.actualReps ?? 0
        self.setCount = workoutExercise.setsList.count
        self.targetMin = workoutExercise.targetRepMin ?? 0
        self.isAssistance = workoutExercise.loadBehavior.isCounterweightAssistance
        self.onApply = onApply
        self.onCancel = onCancel
    }

    /// The current unit's steps. Pounds get their own plate steps rather than
    /// converted kilograms — see `ProgressiveOverloadIncrement`.
    private var grid: ProgressiveOverloadIncrement.Grid {
        ProgressiveOverloadIncrement.grid(for: weightUnit)
    }

    private var increment: Double {
        selectedIncrement ?? grid.defaultOption
    }

    /// `currentWeight` in the displayed unit. Every number this sheet shows is
    /// computed in display space, so the arithmetic the user reads adds up
    /// exactly ("198.4 + 5 = 203.4") instead of drifting through a conversion.
    private var currentDisplayWeight: Double {
        weightUnit.converting(fromKilograms: currentWeight)
    }

    private func resultingDisplayWeight(after increment: Double) -> Double {
        isAssistance
            ? max(0, currentDisplayWeight - increment)
            : currentDisplayWeight + increment
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Current state
                Text("rep_range.current_state".localized(
                    WeightFormatting.displayLabel(currentDisplayWeight, in: weightUnit),
                    currentReps,
                    setCount
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                // Increment options
                VStack(spacing: 8) {
                    ForEach(grid.options, id: \.self) { option in
                        let isSelected = option == increment
                        Button {
                            selectedIncrement = option
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                                    .foregroundStyle(isSelected ? .orange : .secondary)

                                // The seam's two fraction digits, not `%.2g`: at
                                // two SIGNIFICANT digits a 1.25 step renders as
                                // a misleading "1.2".
                                Text("\(isAssistance ? "−" : "+")\(WeightFormatting.incrementLabel(option, in: weightUnit))")
                                    .font(.body.weight(.medium))

                                Spacer()

                                Text(WeightFormatting.displayLabel(resultingDisplayWeight(after: option), in: weightUnit))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isSelected
                                        ? Color.orange.opacity(0.1)
                                        : DesignSystem.Colors.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isSelected
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
                            ? "exercise.assistance.value".localized(
                                WeightFormatting.displayLabel(resultingDisplayWeight(after: increment), in: weightUnit)
                            )
                            : "rep_range.new_state".localized(
                                WeightFormatting.displayLabel(resultingDisplayWeight(after: increment), in: weightUnit),
                                targetMin
                            )
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
                        // The one conversion: the grid lives in display space,
                        // everything below this line is canonical kilograms.
                        onApply(weightUnit.kilograms(fromDisplay: increment))
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
