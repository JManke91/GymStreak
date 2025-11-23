import SwiftUI

struct RoutineDetailView: View {
    let routine: WatchRoutine
    let onStartWorkout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Exercise summary
                exerciseSummary

                // Exercise list
                ForEach(routine.exercises) { exercise in
                    ExercisePreviewRow(exercise: exercise)
                }

                // Start button
                startButton
            }
            .padding(.horizontal)
        }
        .navigationTitle(routine.name)
    }

    // MARK: - Subviews

    private var exerciseSummary: some View {
        HStack {
            VStack {
                Text("\(routine.exerciseCount)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                Text("exercises")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack {
                Text("\(routine.totalSets)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                Text("sets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var startButton: some View {
        Button(action: onStartWorkout) {
            Label("Start Workout", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .padding(.top, 8)
        .accessibilityHint("Double tap to begin workout")
    }
}

// MARK: - Exercise Preview Row

struct ExercisePreviewRow: View {
    let exercise: WatchExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .font(.footnote)
                .lineLimit(1)

            Text("\(exercise.sets.count) sets")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        RoutineDetailView(
            routine: WatchRoutine(
                id: UUID(),
                name: "Push Day",
                exercises: [
                    WatchExercise(
                        id: UUID(),
                        name: "Bench Press",
                        muscleGroup: "Chest",
                        sets: [
                            WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90),
                            WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90),
                            WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90)
                        ],
                        order: 0
                    ),
                    WatchExercise(
                        id: UUID(),
                        name: "Shoulder Press",
                        muscleGroup: "Shoulders",
                        sets: [
                            WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60),
                            WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60)
                        ],
                        order: 1
                    )
                ]
            )
        ) {
            print("Start workout")
        }
    }
}
