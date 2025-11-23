import SwiftUI

struct ExerciseListView: View {
    let exercises: [ActiveWorkoutExercise]
    let currentIndex: Int
    let onSelectExercise: (Int) -> Void
    let onEnd: () -> Void

    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    var body: some View {
        List {
            // Header with overall progress
            Section {
                WorkoutProgressHeader(exercises: exercises)
            }

            // Compact timer integrated into layout
            if viewModel.isResting && viewModel.isRestTimerMinimized {
                Section {
                    CompactRestTimer(
                        timeRemaining: viewModel.restTimeRemaining,
                        totalDuration: viewModel.restDuration,
                        formattedTime: viewModel.formattedRestTime,
                        onSkip: viewModel.skipRest,
                        onExpand: viewModel.expandRestTimer
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Exercise rows
            Section {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    ExerciseRow(
                        exercise: exercise,
                        index: index,
                        isCurrent: index == currentIndex,
                        onTap: { onSelectExercise(index) }
                    )
                }
            }

            // End workout button at bottom
            Section {
                Button(action: onEnd) {
                    HStack {
                        Image(systemName: "flag.checkered")
                            .font(.title3)
                        Text("End Workout")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.orange)
                .listRowBackground(Color.orange.opacity(0.15))
                .accessibilityLabel("End workout")
                .accessibilityHint("Double tap to finish or discard your workout")
            }
        }
        .listStyle(.carousel)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRestTimerMinimized)
    }
}

// MARK: - Workout Progress Header

struct WorkoutProgressHeader: View {
    let exercises: [ActiveWorkoutExercise]

    private var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    private var completedSets: Int {
        exercises.reduce(0) { $0 + $1.completedSetsCount }
    }

    private var progress: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%")
                        .font(.title2.monospacedDigit())
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 60, height: 60)

            Text("\(completedSets)/\(totalSets) sets")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    let exercise: ActiveWorkoutExercise
    let index: Int
    let isCurrent: Bool
    let onTap: () -> Void

    private var status: ExerciseStatus {
        if exercise.isComplete {
            return .completed
        } else if isCurrent {
            return .inProgress
        } else if exercise.completedSetsCount > 0 {
            return .partiallyComplete
        } else {
            return .pending
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                StatusIcon(status: status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .lineLimit(1)

                    Text("\(exercise.completedSetsCount)/\(exercise.sets.count) sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !exercise.isComplete {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listRowBackground(
            isCurrent ? Color.accentColor.opacity(0.15) : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.name), \(status.accessibilityLabel), \(exercise.completedSetsCount) of \(exercise.sets.count) sets completed")
        .accessibilityHint("Double tap to view sets")
    }
}

// MARK: - Status Icon

enum ExerciseStatus {
    case completed
    case inProgress
    case partiallyComplete
    case pending

    var accessibilityLabel: String {
        switch self {
        case .completed: return "Completed"
        case .inProgress: return "In progress"
        case .partiallyComplete: return "Partially complete"
        case .pending: return "Not started"
        }
    }
}

struct StatusIcon: View {
    let status: ExerciseStatus
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Group {
            switch status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .inProgress:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: !reduceMotion)

            case .partiallyComplete:
                Image(systemName: "circle.bottomhalf.filled")
                    .foregroundStyle(.orange)

            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3)
        .accessibilityLabel(status.accessibilityLabel)
    }
}

#Preview {
    NavigationStack {
        ExerciseListView(
            exercises: [
                ActiveWorkoutExercise(
                    id: UUID(),
                    name: "Bench Press",
                    muscleGroup: "Chest",
                    sets: [
                        ActiveWorkoutSet(id: UUID(), plannedReps: 10, actualReps: 10, plannedWeight: 135, actualWeight: 135, restTime: 90, isCompleted: true, completedAt: Date(), order: 0),
                        ActiveWorkoutSet(id: UUID(), plannedReps: 10, actualReps: 10, plannedWeight: 135, actualWeight: 135, restTime: 90, isCompleted: true, completedAt: Date(), order: 1),
                        ActiveWorkoutSet(id: UUID(), plannedReps: 10, actualReps: 10, plannedWeight: 135, actualWeight: 135, restTime: 90, isCompleted: false, completedAt: nil, order: 2)
                    ],
                    order: 0
                ),
                ActiveWorkoutExercise(
                    id: UUID(),
                    name: "Shoulder Press",
                    muscleGroup: "Shoulders",
                    sets: [
                        ActiveWorkoutSet(id: UUID(), plannedReps: 10, actualReps: 10, plannedWeight: 65, actualWeight: 65, restTime: 60, isCompleted: false, completedAt: nil, order: 0),
                        ActiveWorkoutSet(id: UUID(), plannedReps: 10, actualReps: 10, plannedWeight: 65, actualWeight: 65, restTime: 60, isCompleted: false, completedAt: nil, order: 1)
                    ],
                    order: 1
                )
            ],
            currentIndex: 0,
            onSelectExercise: { _ in },
            onEnd: { }
        )
    }
}
