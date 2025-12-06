import SwiftUI

struct ExerciseSetView: View {
    let exercise: ActiveWorkoutExercise?
    let setIndex: Int
    let progress: Double
    let completedSets: Int
    let totalSets: Int
    let onComplete: () -> Void
    let onBack: () -> Void

    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation bar with back button
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Back to exercise list")
                .buttonStyle(.plain)

                Spacer()

                Text(exercise?.name ?? "Complete")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Invisible placeholder for symmetry
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .opacity(0)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Compact timer integrated into layout
            if viewModel.isResting && viewModel.isRestTimerMinimized {
                CompactRestTimer(
                    timeRemaining: viewModel.restTimeRemaining,
                    totalDuration: viewModel.restDuration,
                    formattedTime: viewModel.formattedRestTime,
                    onSkip: viewModel.skipRest,
                    onExpand: viewModel.expandRestTimer
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main content
            VStack(spacing: 8) {
                if let exercise = exercise {
                    // Set progress
                    Text("Set \(setIndex + 1) of \(exercise.sets.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Target info
                    if let currentSet = exercise.sets[safe: setIndex] {
                        setInfo(currentSet)
                    }

                    // Complete button
                    completeButton

                    // Overall progress
                    progressIndicator
                } else {
                    Text("Workout Complete!")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
            .padding()
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRestTimerMinimized)
    }

    // MARK: - Subviews

    private func setInfo(_ set: ActiveWorkoutSet) -> some View {
        HStack(spacing: 16) {
            VStack {
                Text("\(Int(set.plannedWeight))")
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                Text("lbs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Int(set.plannedWeight)) pounds")

            VStack {
                Text("\(set.plannedReps)")
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                Text("reps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(set.plannedReps) reps")
        }
    }

    private var completeButton: some View {
        Button(action: onComplete) {
            Label("Done", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .accessibilityLabel("Complete set")
        .accessibilityHint("Double tap to mark set \(setIndex + 1) as complete")
    }

    private var progressIndicator: some View {
        HStack(spacing: 4) {
            ProgressRing(progress: progress)
                .frame(width: 24, height: 24)

            Text("\(completedSets)/\(totalSets)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

//#Preview {
//    NavigationStack {
//        ExerciseSetView(
//            exercise: ActiveWorkoutExercise(
//                id: UUID(),
//                name: "Bench Press",
//                muscleGroup: "Chest",
//                sets: [
//                    ActiveWorkoutSet(
//                        id: UUID(),
//                        plannedReps: 10,
//                        actualReps: 10,
//                        plannedWeight: 135,
//                        actualWeight: 135,
//                        restTime: 90,
//                        isCompleted: false,
//                        completedAt: nil,
//                        order: 0
//                    )
//                ],
//                order: 0
//            ),
//            setIndex: 0,
//            progress: 0.25,
//            completedSets: 2,
//            totalSets: 8,
//            onComplete: { },
//            onBack: { }
//        )
//    }
//}
