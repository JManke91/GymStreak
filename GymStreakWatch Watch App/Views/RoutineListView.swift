import SwiftUI
import SwiftData

struct RoutineListView: View {
    @Query(sort: \Routine.updatedAt, order: .reverse) var routines: [Routine]
    @EnvironmentObject var workoutViewModel: WatchWorkoutViewModel

    @State private var selectedRoutine: Routine?

    var body: some View {
        Group {
            if routines.isEmpty {
                emptyView
            } else {
                routineList
            }
        }
        .navigationTitle("Routines")
        .fullScreenCover(item: $selectedRoutine) { routine in
            ActiveWorkoutView(routine: routine)
                .environmentObject(workoutViewModel)
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Subviews

    private var routineList: some View {
        List {
            ForEach(routines) { routine in
                NavigationLink(value: routine.id) {
                    RoutineRowView(routine: routine)
                }
            }
        }
        .listStyle(.carousel)
        .navigationDestination(for: UUID.self) { routineId in
            if let routine = routines.first(where: { $0.id == routineId }) {
                RoutineDetailView(routine: routine) {
                    selectedRoutine = routine
                }
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Routines", systemImage: "dumbbell")
        } description: {
            Text("Create routines in GymStreak on your iPhone")
        }
    }
}

// MARK: - Routine Row

struct RoutineRowView: View {
    let routine: Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(routine.name)
                .font(.headline)
                .lineLimit(2)

            Label("\(routine.routineExercisesList.count) exercises", systemImage: "dumbbell.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(routine.name), \(routine.routineExercisesList.count) exercises")
    }
}

#Preview {
    NavigationStack {
        RoutineListView()
            .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self], inMemory: true)
            .environmentObject(WatchWorkoutViewModel.preview)
    }
}
