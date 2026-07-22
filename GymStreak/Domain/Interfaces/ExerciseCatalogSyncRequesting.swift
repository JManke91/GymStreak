//
//  ExerciseCatalogSyncRequesting.swift
//  GymStreak
//
//  What ViewModels use to request an exercise-catalogue sync to the watch
//  after a successfully committed library mutation. Implemented by the
//  composition-root-owned ExerciseCatalogSyncCoordinator — ViewModels never
//  talk to WatchConnectivity directly.
//

import Foundation

@MainActor
protocol ExerciseCatalogSyncRequesting: AnyObject {
    /// Fetches the current committed exercise library and stages a full
    /// snapshot for the watch. Cheap to call; identical content is suppressed
    /// downstream.
    func requestCatalogSync()
}
