import SwiftUI

#Preview {
    let routine = WatchRoutine(
        id: UUID(),
        name: "Push Day",
        exercises: [
            WatchExercise(
                id: UUID(),
                name: "Bench Press",
                muscleGroup: "Chest",
                sets: [
                    WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90),
                    WatchSet(id: UUID(), reps: 10, weight: 135, restTime: 90)
                ],
                order: 0,
                supersetId: nil,
                supersetOrder: 0
            ),
            WatchExercise(
                id: UUID(),
                name: "Shoulder Press",
                muscleGroup: "Shoulders",
                sets: [
                    WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60),
                    WatchSet(id: UUID(), reps: 10, weight: 65, restTime: 60)
                ],
                order: 1,
                supersetId: nil,
                supersetOrder: 0
            )
        ]
    )
    let store: RoutineStore = {
        let store = RoutineStore(syncState: WatchSyncStateStore())
        store.updateRoutines([routine])
        return store
    }()
    let viewModel = WatchWorkoutViewModel(
        healthKitManager: WatchHealthKitManager(),
        connectivityManager: WatchConnectivityManager.shared,
        routineStore: store
    )

    ActiveWorkoutView(routineID: routine.id)
        .environmentObject(viewModel)
        .environmentObject(WatchConnectivityManager.shared.exerciseCatalogStore)
}
