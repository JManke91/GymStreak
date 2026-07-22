//
//  ExerciseCatalogSyncCoordinator.swift
//  GymStreak
//
//  The single long-lived owner of "when does the catalogue sync". Wired at
//  the composition root (AppDependencies) — deliberately NOT a view-scoped
//  ViewModel, because the app creates several ExercisesViewModel instances
//  and catalogue changes also originate from seeding and CloudKit.
//
//  Triggers: after DefaultContentSeeder.run() (called from GymStreakApp),
//  after every successfully committed library mutation (ViewModels call
//  requestCatalogSync()), and on every CloudKit remote change. Each trigger
//  fetches fresh committed repository state — never a view model's array.
//

import Foundation

@MainActor
final class ExerciseCatalogSyncCoordinator: ExerciseCatalogSyncRequesting {
    private let exerciseRepository: ExerciseRepository
    private let watchSync: WatchSyncServicing
    private var cloudSyncObserver: NSObjectProtocol?

    init(exerciseRepository: ExerciseRepository, watchSync: WatchSyncServicing) {
        self.exerciseRepository = exerciseRepository
        self.watchSync = watchSync
        cloudSyncObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestCatalogSync()
            }
        }
    }

    func requestCatalogSync() {
        watchSync.syncExerciseCatalog(exerciseRepository.fetchAll())
    }
}
