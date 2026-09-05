//
//  MuscleMapDiscoveryStore.swift
//  GymStreak
//
//  The durable half of the muscle map's discovery hint: that the gesture has
//  been learned, or that the hint has been spent trying to teach it.
//  See docs/muscle-map.md, "Discoverability".
//

import Foundation

/// Remembers whether the muscle map's tap gesture still needs explaining.
///
/// Plain `UserDefaults.standard`, matching `OnboardingCompletionStore` and
/// `FounderCelebrationStore` — the reasoning for that choice, and against both
/// the App Group suite and iCloud KVS, is on `MuscleMapDiscoveryTracking`.
///
/// Both facts are cached in memory, seeded at init, because the card reads the
/// flag while it is being laid out and `UserDefaults` is not observable.
@MainActor
final class MuscleMapDiscoveryStore: MuscleMapDiscoveryTracking {

    private(set) var hasDiscoveredMuscleMap: Bool
    /// Unused appearances so far. Only ever read to decide whether the next one
    /// is the last, so it stops being maintained once the flag is set.
    private var hintShownCount: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasDiscoveredMuscleMap = defaults.bool(forKey: Self.discoveredKey)
        self.hintShownCount = defaults.integer(forKey: Self.shownCountKey)
    }

    func recordSelection() {
        markDiscovered()
    }

    func recordShown() {
        guard !hasDiscoveredMuscleMap else { return }
        hintShownCount += 1
        defaults.set(hintShownCount, forKey: Self.shownCountKey)
        guard hintShownCount >= Self.unusedShowLimit else { return }
        markDiscovered()
    }

    private func markDiscovered() {
        guard !hasDiscoveredMuscleMap else { return }
        hasDiscoveredMuscleMap = true
        defaults.set(true, forKey: Self.discoveredKey)
    }

    /// Three appearances is the whole budget, counted across both screens
    /// together. The appearance that reaches the limit still shows the hint —
    /// the card reads the flag before it records — so the user gets a first, a
    /// second and a third look, and nothing on the fourth.
    static let unusedShowLimit = 3

    private static let discoveredKey = "muscleMap.gestureDiscovered"
    private static let shownCountKey = "muscleMap.hintShownCount"
}
