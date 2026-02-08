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
//                    .frame(height: 80)
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
                .foregroundStyle(OnyxWatch.Colors.warning)
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
    @EnvironmentObject var viewModel: WatchWorkoutViewModel
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
        if viewModel.workoutState == .started { //
//            Text("hello world")
//            ProgressView("Loading...") // Shows spinner with optional text
//                .progressViewStyle(CircularProgressViewStyle())
//            ZStack {
//                        Color.black.opacity(0.3)
//                            .ignoresSafeArea()
//                            .blur(radius: 2)
//                            .frame(height: 60)

            HStack(spacing: 14) {
                ModernSpinner()
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 10)

                Text("Loading Metrics")
            }

//                    }
//                .frame(height: 60)
        } else {
            HStack {
                // Heart rate now updates because this view observes the environment object
    //            Text("heart: \(viewModel.currentHeartRate)")
                VStack {
                    if let heartRate = viewModel.heartRate, let calories = viewModel.activeCalories {
                        WorkoutMetricsView(heartRate: heartRate, calories: calories)
    //                        VStack(spacing: 5) {
    //                            Image(systemName: "heart.fill")
    //                                .resizable()
    //                                .foregroundColor(.red)
    //                                .frame(width: 15, height: 15)
    //                                .symbolEffect(.breathe)
    //
    //                            HStack(spacing: 3) {
    //                                Text("\(heartRate)")
    //                                    .font(.system(size: 18, weight: .bold))
    //                                Text("BPM")
    //                                    .font(.system(size: 12, weight: .light))
    //                            }
    //
    //                            Image(systemName: "flame")
    //                                .resizable()
    //                                .foregroundColor(.orange)
    //                                .frame(width: 15, height: 15)
    //                                .symbolEffect(.breathe)
    //                            HStack(spacing: 3) {
    //                                Text("\(calories)")
    //                                    .font(.system(size: 18, weight: .bold))
    //                                Text("kCal")
    //                                    .font(.system(size: 12, weight: .light))
    //                            }
    //                        }
    //                    }
                    }
                    // FIXME: does not work yet
    //                .transition(.asymmetric(insertion: .scale, removal: .opacity))
    //                .animation(.easeInOut(duration: 5.0))
                }

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(OnyxWatch.Colors.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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


    }
}

enum WorkoutMetricsSize {
    case medium
    case small
}

import SwiftUI

struct ModernSpinner: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.7) // part of a circle
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.cyan, Color.blue, Color.cyan]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
//                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}


struct WorkoutMetricsView: View {
    let heartRate: Int
    let calories: Int
    var size: WorkoutMetricsSize = .medium

    var body: some View {
        VStack(spacing: 5) {
            if size == .medium {
                Image(systemName: "heart.fill")
                    .resizable()
                    .foregroundColor(.red)
                    .frame(width: size == .medium ? 15 : 10, height: size == .medium ? 15 : 10)
                    .symbolEffect(.breathe)
            }


            HStack(spacing: 3) {
                if size == .small {
                    Image(systemName: "heart.fill")
                        .resizable()
                        .foregroundColor(.red)
                        .frame(width: size == .medium ? 15 : 10, height: size == .medium ? 15 : 10)
                        .symbolEffect(.breathe)
                }
                Text("\(heartRate)")
                    .font(.system(size: size == .medium ? 18 : 14, weight: .bold))
                Text("BPM")
                    .font(.system(size: size == .medium ? 12 : 10, weight: .light))
            }

            if size == .medium {
                Image(systemName: "flame")
                    .resizable()
                    .foregroundColor(.orange)
                    .frame(width: size == .medium ? 15 : 10, height: size == .medium ? 15 : 10)
                    .symbolEffect(.breathe)
            }

            HStack(spacing: 3) {
                if size == .small {
                    Image(systemName: "flame")
                        .resizable()
                        .foregroundColor(.orange)
                        .frame(width: size == .medium ? 15 : 10, height: size == .medium ? 15 : 10)
                        .symbolEffect(.breathe)
                }
                Text("\(calories)")
                    .font(.system(size: size == .medium ? 18 : 14, weight: .bold))
                Text("kCal")
                    .font(.system(size: size == .medium ? 12 : 10, weight: .light))
            }
        }
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
                    .foregroundStyle(OnyxWatch.Colors.success)

            case .inProgress:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(OnyxWatch.Colors.tint)
                    .symbolEffect(.pulse, isActive: !reduceMotion)

            case .partiallyComplete:
                Image(systemName: "circle.bottomhalf.filled")
                    .foregroundStyle(OnyxWatch.Colors.warning)

            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3)
        .accessibilityLabel(status.accessibilityLabel)
    }
}
