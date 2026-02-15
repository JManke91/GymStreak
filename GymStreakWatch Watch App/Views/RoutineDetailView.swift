import SwiftUI

struct RoutineDetailView: View {
    let routine: WatchRoutine
    let onStartWorkout: () -> Void

    /// Groups exercises by superset - exercises with same supersetId are grouped together
    private var exerciseGroups: [[WatchExercise]] {
        var groups: [[WatchExercise]] = []
        var processedSupersetIds: Set<UUID> = []
        let sorted = routine.exercises.sorted { $0.order < $1.order }

        for exercise in sorted {
            if let supersetId = exercise.supersetId {
                guard !processedSupersetIds.contains(supersetId) else { continue }
                processedSupersetIds.insert(supersetId)

                let supersetExercises = sorted
                    .filter { $0.supersetId == supersetId }
                    .sorted { $0.supersetOrder < $1.supersetOrder }
                groups.append(supersetExercises)
            } else {
                groups.append([exercise])
            }
        }
        return groups
    }

    var body: some View {
        // Main scrollable content; no large bottom spacer required because safeAreaInset reserves space
        ScrollView {
            VStack(spacing: 12) {
                // Exercise summary
                exerciseSummary

                // Exercise list grouped by supersets
                ForEach(Array(exerciseGroups.enumerated()), id: \.offset) { _, group in
                    if group.count > 1 {
                        // Superset group
                        SupersetGroupView(exercises: group)
                    } else if let exercise = group.first {
                        // Single exercise in card
                        ExercisePreviewRow(exercise: exercise, showSupersetBadge: false)
                            .background(
                                RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusSM)
                                    .fill(OnyxWatch.Colors.card)
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(routine.name)
        .safeAreaInset(edge: .bottom) {
            startButton
                .frame(height: 36)
                .padding(.horizontal, 8)
        }
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
        .tint(OnyxWatch.Colors.textOnTint)
        .controlSize(.small)
        .background(
            LinearGradient(
                colors: [
                    OnyxWatch.Colors.tint,
                    OnyxWatch.Colors.tint.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Capsule())
        .overlay(
            ShimmerView()
                .clipShape(Capsule())
        )
        .padding(.top, 24)
    }
}

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .white.opacity(0.4), location: 0.5),
                    .init(color: .clear, location: 0.7),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .rotationEffect(.degrees(20))
            .offset(x: phase * (geometry.size.width * 2.5) - geometry.size.width * 1.25)
            .blendMode(.overlay)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(0.5)
            ) {
                phase = 1
            }
        }
    }
}

// MARK: - Superset Group View

struct SupersetGroupView: View {
    let exercises: [WatchExercise]

    var body: some View {
        VStack(spacing: 0) {
            // Superset header
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .bold))
                Text("Superset (\(exercises.count))")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(OnyxWatch.Colors.tint)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Exercises in superset
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                ExercisePreviewRow(
                    exercise: exercise,
                    showSupersetBadge: true,
                    supersetPosition: index + 1,
                    supersetTotal: exercises.count
                )

                // Divider between exercises (except last)
                if index < exercises.count - 1 {
                    Rectangle()
                        .fill(OnyxWatch.Colors.tint.opacity(0.3))
                        .frame(height: 1)
                        .padding(.leading, 8)
                }
            }

            Spacer().frame(height: 2)
        }
        .background(
            RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusSM)
                .fill(OnyxWatch.Colors.tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusSM)
                .strokeBorder(OnyxWatch.Colors.tint.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Exercise Preview Row

struct ExercisePreviewRow: View {
    let exercise: WatchExercise
    var showSupersetBadge: Bool = false
    var supersetPosition: Int = 0
    var supersetTotal: Int = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(exercise.name)
                        .font(.footnote)
                        .lineLimit(1)

                    // Superset position badge (when part of a grouped superset)
                    if showSupersetBadge {
                        Text("\(supersetPosition)/\(supersetTotal)")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(OnyxWatch.Colors.textOnTint)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(OnyxWatch.Colors.tint.opacity(0.8))
                            )
                    }
                }

                HStack(spacing: 4) {
                    Text("\(exercise.sets.count) sets")
                    Text("·")
                    Text(exercise.muscleGroup)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, showSupersetBadge ? 4 : 6)
    }
}

#Preview {
    let supersetId = UUID()

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
                        order: 0,
                        supersetId: nil,
                        supersetOrder: 0
                    ),
                    // Superset exercises
                    WatchExercise(
                        id: UUID(),
                        name: "Bicep Curls",
                        muscleGroup: "Biceps",
                        sets: [
                            WatchSet(id: UUID(), reps: 12, weight: 25, restTime: 60),
                            WatchSet(id: UUID(), reps: 12, weight: 25, restTime: 60)
                        ],
                        order: 1,
                        supersetId: supersetId,
                        supersetOrder: 0
                    ),
                    WatchExercise(
                        id: UUID(),
                        name: "Tricep Pushdowns",
                        muscleGroup: "Triceps",
                        sets: [
                            WatchSet(id: UUID(), reps: 12, weight: 30, restTime: 60),
                            WatchSet(id: UUID(), reps: 12, weight: 30, restTime: 60)
                        ],
                        order: 2,
                        supersetId: supersetId,
                        supersetOrder: 1
                    ),
                    WatchExercise(
                        id: UUID(),
                        name: "Shoulder Press",
                        muscleGroup: "Shoulders",
                        sets: [
                            WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60),
                            WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60)
                        ],
                        order: 3,
                        supersetId: nil,
                        supersetOrder: 0
                    )
                ]
            )
        ) {
            print("Start workout")
        }
    }
}
