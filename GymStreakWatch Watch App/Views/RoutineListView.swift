import SwiftUI

// Wrapper to distinguish workout navigation from routine detail navigation
struct WorkoutDestination: Hashable {
    let routine: WatchRoutine
}

struct RoutineListView: View {
    @EnvironmentObject var routineStore: RoutineStore
    @EnvironmentObject var workoutViewModel: WatchWorkoutViewModel

    @State private var selectedRoutine: WatchRoutine?
    @State private var showWorkout = false

    var body: some View {
        Group {
            if routineStore.isLoading {
                loadingView
            } else if routineStore.routines.isEmpty {
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
            ForEach(routineStore.routines) { routine in
                NavigationLink(value: routine) {
                    RoutineRowView(routine: routine)
                }
            }
        }
        .listStyle(.carousel)
        .navigationDestination(for: WatchRoutine.self) { routine in
            RoutineDetailView(routine: routine) {
                selectedRoutine = routine
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Syncing...")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    let routine: WatchRoutine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(routine.name)
                .font(.headline)
                .lineLimit(2)

            Label("\(routine.exerciseCount) exercises", systemImage: "dumbbell.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(routine.name), \(routine.exerciseCount) exercises")
    }
}

#Preview {
    NavigationStack {
        RoutineListView()
            .environmentObject(RoutineStore())
            .environmentObject(WatchWorkoutViewModel(
                healthKitManager: WatchHealthKitManager(),
                connectivityManager: WatchConnectivityManager.shared
            ))
    }
}
