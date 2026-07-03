//
//  WeightIncreaseSheet.swift
//  GymStreak
//

import SwiftUI

struct WeightIncreaseSheet: View {
    let routineExercise: RoutineExercise
    let onApply: (Double) -> Void
    let onCancel: () -> Void

    @State private var selectedIncrement: Double = 2.5

    private let increments: [Double] = [1.25, 2.5, 5.0]

    private var currentWeight: Double {
        routineExercise.setsList.first?.weight ?? 0
    }

    private var currentReps: Int {
        routineExercise.setsList.first?.reps ?? 0
    }

    private var setCount: Int {
        routineExercise.setsList.count
    }

    private var targetMin: Int {
        routineExercise.targetRepMin ?? 0
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

                                Text("+\(String(format: "%.2g", increment)) kg")
                                    .font(.body.weight(.medium))

                                Spacer()

                                Text("\(String(format: "%.1f", currentWeight + increment)) kg")
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
                    Text("rep_range.new_state".localized(
                        String(format: "%.1f", currentWeight + selectedIncrement),
                        targetMin
                    ))
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
