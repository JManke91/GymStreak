//
//  RoutineStore.swift
//  GymStreakWatch Watch App
//
//  Published projection of the routines the watch UI must show. Since ticket
//  05 it owns NO persistence of its own: the authoritative routine base, the
//  pending template transactions folded over it, and the routine authority
//  all live in the single watch sync-state owner (`WatchSyncStateStore`), so
//  an ordinary or delayed routine context can never erase a pending
//  optimistic value and no second copy of the routines can drift.
//
//  `routines` therefore always equals `WatchSyncStateStore.effectiveRoutines()`
//  — the newest accepted base with every unresolved template transaction
//  folded back over it.
//

import Foundation
import Combine

@MainActor
final class RoutineStore: ObservableObject {
    @Published private(set) var routines: [WatchRoutine] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastSyncDate: Date?

    private let syncState: WatchSyncStateStore

    init(syncState: WatchSyncStateStore) {
        self.syncState = syncState
        syncState.onEffectiveRoutinesChanged = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func routine(for id: UUID) -> WatchRoutine? {
        routines.first { $0.id == id }
    }

    /// Seeds routines locally (watch UI testing / previews). A real routine
    /// list only ever enters through the authority-checked context path in
    /// `WatchConnectivityManager`.
    func updateRoutines(_ newRoutines: [WatchRoutine]) {
        syncState.applyRoutineContext(newRoutines, header: nil)
    }

    private func refresh() {
        routines = syncState.effectiveRoutines()
        lastSyncDate = syncState.lastRoutineSyncDate
    }
}
