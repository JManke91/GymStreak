//
//  InlineSetEditorView.swift
//  GymStreakWatch Watch App
//
//  Created by Claude Code
//

import SwiftUI
import WatchKit

/// Inline editor for adjusting weight and reps of a workout set
/// Displays directly in the set list, eliminating the need for modal sheets
struct InlineSetEditorView: View {
    @Binding var set: ActiveWorkoutSet
    let onComplete: () -> Void

    @State private var focusedField: Field = .weight

    enum Field {
        case weight, reps
    }

    var body: some View {
        VStack(spacing: 12) {
            // Weight stepper
            ValueStepperView(
                label: "WEIGHT",
                value: $set.actualWeight,
                unit: "lbs",
                range: 0...999,
                step: 5,
                isFocused: focusedField == .weight,
                onFocusTap: {
                    focusedField = .weight
                }
            )

            // Reps stepper
            ValueStepperView(
                label: "REPS",
                value: Binding(
                    get: { Double(set.actualReps) },
                    set: { set.actualReps = Int($0) }
                ),
                unit: "reps",
                range: 0...100,
                step: 1,
                isFocused: focusedField == .reps,
                onFocusTap: {
                    focusedField = .reps
                }
            )

            // Complete Set button
            Button {
                completeSet()
            } label: {
                Label("Complete Set", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .accessibilityLabel("Complete set")
            .accessibilityHint("Double tap to mark this set as complete and start rest timer")
        }
        .padding(.vertical, 8)
    }

    /// Completes the set with haptic feedback
    private func completeSet() {
        WKInterfaceDevice.current().play(.success)
        onComplete()
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var set = ActiveWorkoutSet(
            id: UUID(),
            plannedReps: 10,
            actualReps: 10,
            plannedWeight: 135,
            actualWeight: 135,
            restTime: 90,
            isCompleted: false,
            completedAt: nil,
            order: 0
        )

        var body: some View {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set 1")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        InlineSetEditorView(
                            set: $set,
                            onComplete: {
                                print("Set completed")
                            }
                        )
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}
