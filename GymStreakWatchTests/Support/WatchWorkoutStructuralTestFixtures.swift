//
//  WatchWorkoutStructuralTestFixtures.swift
//  GymStreakWatchTests
//
//  Watch-side twin of `GymStreakTests/Support/WatchWorkoutStructuralTestFixtures.swift`.
//  Deliberately built against the *watch* copies of the structural models so a
//  divergence in either copy's initialiser shows up as a compile error here.
//

import Foundation
@testable import GymStreakWatch_Watch_App

@MainActor
extension WatchWorkoutStructuralReducerTests {
    func makeCatalogItem(
        id: UUID = UUID(),
        seedKey: String? = nil,
        name: String
    ) -> WatchExerciseCatalogItem {
        WatchExerciseCatalogItem(
            id: id,
            seedKey: seedKey,
            name: name,
            muscleGroups: ["Chest"],
            equipmentTypeRaw: "barbell",
            loadBehaviorRaw: "resistance"
        )
    }

    func makeWatchExercise(
        id: UUID,
        order: Int,
        isPending: Bool = false
    ) -> WatchExercise {
        WatchExercise(
            id: id,
            name: "Exercise \(order)",
            muscleGroup: "General",
            sets: [WatchSet(id: UUID(), reps: 10, weight: 0, restTime: 60)],
            order: order,
            supersetId: nil,
            supersetOrder: 0,
            exerciseId: UUID(),
            isPendingWatchAddition: isPending
        )
    }

    func makeActiveExercise(
        id: UUID = UUID(),
        exerciseID: UUID? = UUID(),
        seedKey: String? = nil,
        name: String = "Exercise",
        order: Int = 0,
        supersetID: UUID? = nil,
        supersetOrder: Int = 0,
        setCompleted: Bool = false
    ) -> ActiveWorkoutExercise {
        ActiveWorkoutExercise(
            id: id,
            name: name,
            muscleGroup: "General",
            sets: [ActiveWorkoutSet(
                id: UUID(),
                plannedReps: 10,
                actualReps: 10,
                plannedWeight: 0,
                actualWeight: 0,
                restTime: 60,
                completedAt: setCompleted ? Date() : nil,
                order: 0
            )],
            order: order,
            supersetId: supersetID,
            supersetOrder: supersetOrder,
            exerciseId: exerciseID,
            exerciseSeedKey: seedKey
        )
    }
}

@MainActor
extension WatchExercise {
    func toTestActive() -> ActiveWorkoutExercise {
        ActiveWorkoutExercise(
            id: id,
            name: name,
            muscleGroup: muscleGroup,
            sets: sets.enumerated().map { index, set in
                ActiveWorkoutSet(
                    id: set.id,
                    plannedReps: set.reps,
                    actualReps: set.reps,
                    plannedWeight: set.weight,
                    actualWeight: set.weight,
                    restTime: set.restTime,
                    completedAt: nil,
                    order: index
                )
            },
            order: order,
            supersetId: supersetId,
            supersetOrder: supersetOrder,
            exerciseId: exerciseId,
            exerciseSeedKey: exerciseSeedKey,
            isPendingWatchAddition: isPendingWatchAddition ?? false
        )
    }
}
