//
//  WatchMuscleGroupLocalizationTests.swift
//  GymStreakWatchTests
//
//  iOS syncs muscle groups to the watch as raw English keys and each side
//  localizes at display time: `MuscleGroups.displayName(for:)` on iOS,
//  `localizedWatchMuscleGroup(_:)` here. That makes the two tables twins, and a
//  key present on one side but missing on the other renders as a raw English
//  string on a German watch — exactly the bug this file guards against.
//
//  The iOS key list is mirrored as a literal below because the watch target may
//  not import iOS `Domain/` (see docs/watch-unit-tests.md § anti-drift).
//

import Testing
import Foundation
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchMuscleGroupLocalizationTests {

    /// Mirror of iOS `MuscleGroups.localizationKeys` / `allKeys`
    /// (`GymStreak/Domain/Models/MuscleGroups.swift`). Update both together.
    private let iOSMuscleGroupKeys: Set<String> = [
        "Biceps",
        "Triceps",
        "Forearms",
        "Chest",
        "Upper Chest",
        "Upper Back",
        "Lats",
        "Lower Back",
        "Shoulders",
        "Front Delts",
        "Side Delts",
        "Rear Delts",
        "Abs",
        "Obliques",
        "Quadriceps",
        "Hamstrings",
        "Glutes",
        "Calves",
        "Hip Flexors"
    ]

    @Test("Every known muscle group key resolves to a non-empty display name")
    func everyKeyResolves() {
        for key in watchMuscleGroupKeys {
            #expect(!localizedWatchMuscleGroup(key).isEmpty, "empty display name for \(key)")
        }
    }

    @Test("An unknown muscle group passes through unchanged")
    func unknownKeyPassesThrough() {
        #expect(localizedWatchMuscleGroup("Rotator Cuff") == "Rotator Cuff")
        #expect(localizedWatchMuscleGroup("") == "")
    }

    /// Under an English test locale a localized value is indistinguishable from
    /// a passed-through key, so coverage is asserted against the catalog itself:
    /// a key with no entry is exactly how a German watch ends up showing
    /// English. `General` is included because the wire sends it whenever an
    /// exercise has no primary muscle group.
    @Test("Every key the table handles has a String Catalog entry")
    func catalogHasAnEntryForEveryKey() {
        let missing = "__missing__"
        for key in watchMuscleGroupKeys + ["General"] {
            let value = Bundle.main.localizedString(forKey: key, value: missing, table: nil)
            #expect(value != missing, "no Localizable.xcstrings entry for \(key)")
        }
    }

    @Test("The watch table covers exactly the iOS muscle group keys")
    func keySetMatchesIOS() {
        #expect(Set(watchMuscleGroupKeys) == iOSMuscleGroupKeys)
    }

    @Test("The watch table lists no key twice")
    func keysAreUnique() {
        #expect(Set(watchMuscleGroupKeys).count == watchMuscleGroupKeys.count)
    }
}
