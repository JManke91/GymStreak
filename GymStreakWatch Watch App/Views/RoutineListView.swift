import SwiftUI

private struct RoutineDestination: Hashable {
    let routineID: UUID
}

private struct WorkoutDestination: Identifiable {
    let routineID: UUID

    var id: UUID { routineID }
}

struct RoutineListView: View {
    @EnvironmentObject var routineStore: RoutineStore
    @EnvironmentObject var workoutViewModel: WatchWorkoutViewModel

    @State private var workoutDestination: WorkoutDestination?

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
        // `onDismiss` is the documented, single-fire signal for an actual
        // cover dismissal (unlike `.onDisappear`, which can fire on wrist-down
        // and would wrongly kill a live workout). It's a safety net: the
        // primary exit now runs through the End-Workout confirmation (see the
        // cancellationAction button in ActiveWorkoutView). If the cover is ever
        // closed while a workout is still live and unfinalized, tear the
        // HealthKit session down so it can't keep running in the background and
        // block starting another workout. No-op once the workout is finalized,
        // discarded, or frozen mid-finalization (`discardWorkout` guards that).
        .fullScreenCover(item: $workoutDestination, onDismiss: {
            if workoutViewModel.isWorkoutActive && workoutViewModel.workoutSummary == nil {
                workoutViewModel.discardWorkout()
            }
        }) { destination in
            ActiveWorkoutView(routineID: destination.routineID)
                .environmentObject(workoutViewModel)
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Subviews

    private var routineList: some View {
        // iOS syncs routines with the up-next routine (next planned workout,
        // or least recently trained as fallback) first — see
        // RoutinesViewModel.syncRoutinesToWatch(). The first routine is
        // therefore surfaced as the "Up Next" hero with a quick-start button.
        List {
            if let upNext = routineStore.routines.first {
                Section {
                    NavigationLink(value: RoutineDestination(routineID: upNext.id)) {
                        RoutineRowView(routine: upNext)
                    }
                    quickStartButton(for: upNext)
                } header: {
                    Text("Up Next")
                }
            }

            if routineStore.routines.count > 1 {
                Section {
                    ForEach(routineStore.routines.dropFirst()) { routine in
                        NavigationLink(value: RoutineDestination(routineID: routine.id)) {
                            RoutineRowView(routine: routine)
                        }
                    }
                } header: {
                    Text("All Routines")
                }
            }
        }
        .listStyle(.carousel)
        .navigationDestination(for: RoutineDestination.self) { destination in
            RoutineDetailDestination(routineID: destination.routineID) { latestRoutineID in
                startWorkout(routineID: latestRoutineID)
            }
        }
    }

    private func quickStartButton(for routine: WatchRoutine) -> some View {
        Button {
            startWorkout(routineID: routine.id)
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .font(.watchSubheadline)
                .foregroundStyle(OnyxWatch.Colors.textOnTint)
                .frame(maxWidth: .infinity)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusLG)
                .fill(
                    LinearGradient(
                        colors: [
                            OnyxWatch.Colors.tint,
                            OnyxWatch.Colors.tint.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .accessibilityLabel("Start workout \(routine.name)")
    }

    /// A navigation row carries only stable identity. Resolving the routine at
    /// the moment the workout starts prevents an already-open detail screen
    /// from launching with the value snapshot that originally opened it.
    private func startWorkout(routineID: UUID) {
        guard routineStore.routine(for: routineID) != nil else { return }
        workoutDestination = WorkoutDestination(routineID: routineID)
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

/// Keeps an open routine detail screen subscribed to the store and resolves
/// its value by identity on every render. `WatchRoutine` is a value type, so
/// putting the whole routine in `NavigationPath` freezes the old set values
/// until that path is rebuilt (which previously happened only after relaunch).
private struct RoutineDetailDestination: View {
    @EnvironmentObject private var routineStore: RoutineStore

    let routineID: UUID
    let onStartWorkout: (UUID) -> Void

    var body: some View {
        if let routine = routineStore.routine(for: routineID) {
            RoutineDetailView(routine: routine) {
                onStartWorkout(routineID)
            }
        } else {
            ProgressView()
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
            .environmentObject(RoutineStore(syncState: WatchSyncStateStore()))
            .environmentObject(WatchWorkoutViewModel(
                healthKitManager: WatchHealthKitManager(),
                connectivityManager: WatchConnectivityManager.shared,
                routineStore: RoutineStore(syncState: WatchSyncStateStore())
            ))
    }
}
