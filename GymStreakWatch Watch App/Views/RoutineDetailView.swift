import SwiftUI
import SwiftData

struct RoutineDetailView: View {
    let routine: Routine
    let onStartWorkout: () -> Void

    /// Groups exercises by superset using the model's built-in grouping
    private var exerciseGroups: [[RoutineExercise]] {
        routine.exercisesGroupedBySupersets
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
                Text("\(routine.routineExercisesList.count)")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                Text("exercises")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack {
                Text("\(routine.routineExercisesList.reduce(0) { $0 + $1.setsList.count })")
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
    let exercises: [RoutineExercise]

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
    let exercise: RoutineExercise
    var showSupersetBadge: Bool = false
    var supersetPosition: Int = 0
    var supersetTotal: Int = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(exercise.exercise?.name ?? "Unknown")
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
                    Text("\(exercise.setsList.count) sets")
                    Text("·")
                    Text(exercise.exercise?.primaryMuscleGroup ?? "General")
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
    NavigationStack {
        Text("Preview requires SwiftData container")
    }
}
