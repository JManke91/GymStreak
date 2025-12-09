import SwiftUI

struct RoutineDetailView: View {
    let routine: WatchRoutine
    let onStartWorkout: () -> Void

    var body: some View {
        // Main scrollable content; no large bottom spacer required because safeAreaInset reserves space
        ScrollView {
            VStack(spacing: 12) {
                // Exercise summary
                exerciseSummary

                // Exercise list
                ForEach(routine.exercises) { exercise in
                    ExercisePreviewRow(exercise: exercise)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(routine.name)
        // Floating start button pinned to bottom; small, without a rectangular background
        .safeAreaInset(edge: .bottom) {
//            HStack {
//                Spacer()

            startButton
                    // Make the floating button slightly smaller than before
//                    .controlSize(.regular)
                    .frame(height: 36)
                    // remove extra background—keep it compact
                    .padding(.horizontal, 8)

//                Spacer()
//            }
//            .padding(.bottom, 6)
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
        .tint(.white)
        .controlSize(.small)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.0, green: 0.6, blue: 1.0), // light blue
                    Color(red: 0.0, green: 0.3, blue: 0.8)  // darker blue
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
//        .accessibilityHint("Double tap to begin workout")
    }

//    private var nweStartButton: some View {
//        Button(action: onStartWorkout) {
//            HStack {
//                Image(systemName: "play.fill")
//                    .font(.title2.bold())
//                Text("Start Workout")
//                    .fontWeight(.semibold)
//            }
////            .foregroundColor(.white)
//            .padding(.vertical, 10)
//            .padding(.horizontal, 20)
//            .background(
//                LinearGradient(
//                    colors: [Color.red, Color.orange],
//                    startPoint: .topLeading,
//                    endPoint: .bottomTrailing
//                )
//            )
//            .clipShape(Capsule())
////            .shadow(color: Color.orange.opacity(0.5), radius: 5, x: 0, y: 3)
////            .overlay(
////                Capsule()
////                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
////            )
//        }
//    }
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
