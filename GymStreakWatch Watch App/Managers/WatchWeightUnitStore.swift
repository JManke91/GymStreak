//
//  WatchWeightUnitStore.swift
//  GymStreakWatch Watch App
//
//  Published projection of the weight unit the iPhone last sent. See
//  docs/weight-unit-preference.md and docs/watch-sync.md.
//

import Foundation
import Combine

/// The unit every weight on this watch is shown and entered in.
///
/// It owns no persistence of its own — like `RoutineStore`, it is a projection
/// of the single watch sync-state owner (`WatchSyncStateStore`), which persists
/// the unit alongside the routine base so both survive a relaunch and are
/// available before the first `applicationContext` of the session arrives.
///
/// The watch never derives the unit from its own `Locale`: that is precisely
/// what made a US-locale watch render "80 lb" in the routine overview while its
/// set editor said "kg". Until iOS has published one, the unit is kilograms —
/// the canonical stored unit, so untranslated numbers are still true.
@MainActor
final class WatchWeightUnitStore: ObservableObject {
    @Published private(set) var unit: WeightUnit

    private let syncState: WatchSyncStateStore

    init(syncState: WatchSyncStateStore) {
        self.syncState = syncState
        self.unit = syncState.weightUnit
        syncState.onWeightUnitChanged = { [weak self] in
            guard let self else { return }
            self.unit = self.syncState.weightUnit
        }
    }
}
