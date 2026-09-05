//
//  MuscleMapDiscoveryStoreTests.swift
//  GymStreakTests
//
//  The muscle map's one-time discovery hint (docs/muscle-map.md,
//  "Discoverability").
//
//  Two ways out of the hint, and the second is the one worth guarding: the user
//  taps a region, or three appearances go by unused. Without the second, a user
//  who never taps is shown explanatory chrome on every workout and every routine
//  forever — the permanent chrome this design was chosen to avoid, arriving by
//  the back door.
//
//  These run against the real store over a throwaway defaults suite, because
//  "spent" is a property of what was written down and a double would assert it
//  away.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct MuscleMapDiscoveryStoreTests {

    // MARK: - The starting state

    @Test("A fresh install has not discovered the gesture")
    func freshInstallIsUndiscovered() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        #expect(!store.hasDiscoveredMuscleMap)
    }

    // MARK: - Dismissal by use

    @Test("Selecting a region retires the hint")
    func selectionRetiresTheHint() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        store.recordSelection()

        #expect(store.hasDiscoveredMuscleMap)
    }

    @Test("Selecting again changes nothing")
    func selectionIsIdempotent() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        store.recordSelection()
        store.recordSelection()
        store.recordSelection()

        #expect(store.hasDiscoveredMuscleMap)
    }

    @Test("An appearance counted after a selection does not un-teach the gesture")
    func showAfterSelectionDoesNotReopenTheHint() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        store.recordSelection()
        store.recordShown()
        store.recordShown()
        store.recordShown()
        store.recordShown()

        #expect(store.hasDiscoveredMuscleMap)
    }

    // MARK: - Dismissal by exhaustion

    @Test("The first two unused appearances leave the hint in place")
    func hintSurvivesTwoUnusedAppearances() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        store.recordShown()
        #expect(!store.hasDiscoveredMuscleMap)

        store.recordShown()
        #expect(!store.hasDiscoveredMuscleMap)
    }

    @Test("The third unused appearance spends the hint")
    func thirdUnusedAppearanceSpendsTheHint() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        store.recordShown()
        store.recordShown()
        store.recordShown()

        #expect(store.hasDiscoveredMuscleMap)
    }

    @Test("Counting past the limit stays retired")
    func countingPastTheLimitStaysRetired() {
        let store = MuscleMapDiscoveryStore(defaults: makeDefaults())

        for _ in 0..<10 {
            store.recordShown()
        }

        #expect(store.hasDiscoveredMuscleMap)
    }

    // MARK: - Persistence

    @Test("A selection survives a relaunch")
    func selectionSurvivesRelaunch() {
        let defaults = makeDefaults()
        MuscleMapDiscoveryStore(defaults: defaults).recordSelection()

        // A fresh store over the same defaults — the next launch.
        let next = MuscleMapDiscoveryStore(defaults: defaults)

        #expect(next.hasDiscoveredMuscleMap)
    }

    @Test("The appearance count survives a relaunch, so the budget is not restarted")
    func appearanceCountSurvivesRelaunch() {
        let defaults = makeDefaults()

        MuscleMapDiscoveryStore(defaults: defaults).recordShown()
        MuscleMapDiscoveryStore(defaults: defaults).recordShown()

        // The third appearance happens on a third launch and still lands on the
        // limit — the count is durable, not per-instance.
        let third = MuscleMapDiscoveryStore(defaults: defaults)
        #expect(!third.hasDiscoveredMuscleMap)
        third.recordShown()

        #expect(third.hasDiscoveredMuscleMap)
        #expect(MuscleMapDiscoveryStore(defaults: defaults).hasDiscoveredMuscleMap)
    }

    /// A throwaway suite per test: the real store writes `UserDefaults.standard`,
    /// which the developer's simulator shares.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MuscleMapDiscoveryStoreTests.\(UUID().uuidString)")!
    }
}
