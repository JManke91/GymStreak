//
//  MuscleMapCardModelTests.swift
//  GymStreakTests
//
//  `MuscleMapCardModel.make(from:reading:)` is what makes one card serve two screens: the
//  reading selects a set of localization keys and everything downstream is built from it. A
//  typo'd key renders the raw key string with a perfectly green build, so the selection is
//  asserted here rather than left to whoever next opens the routine screen.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct MuscleMapCardModelTests {

    /// Chest led by one exercise, shoulders supporting it — enough to produce a primary pill, a
    /// primary detail chip, a secondary one, and idle regions.
    private static let loads: [MuscleMapRegion: MuscleLoad] = [
        .chest: MuscleLoad(engagement: .primary, setCount: 8, exerciseNames: ["Bankdrücken"]),
        .shoulders: MuscleLoad(engagement: .secondary, setCount: 0, exerciseNames: ["Bankdrücken"]),
    ]

    private static func model(_ reading: MuscleMapReading) -> MuscleMapCardModel {
        .make(from: loads, reading: reading)
    }

    // MARK: - The reading actually reaches the strings

    @Test("Each reading titles the card from its own key, and neither leaks a raw key")
    func titlesComeFromTheReading() {
        let performed = Self.model(.performed)
        let planned = Self.model(.planned)

        #expect(performed.title == "history.detail.muscle_map.title".localized)
        #expect(planned.title == "routine.detail.muscle_map.title".localized)
        #expect(performed.title != "history.detail.muscle_map.title")
        #expect(planned.title != "routine.detail.muscle_map.title")
        #expect(performed.title != planned.title)
    }

    @Test("A primary region's set count is phrased as planned only in the planned reading")
    func setCountsArePhrasedByReading() {
        let performed = Self.model(.performed).details[.chest]
        let planned = Self.model(.planned).details[.chest]

        #expect(performed?.stateLabel == String(format: "history.detail.muscle_map.sets_count".localized, 8))
        #expect(planned?.stateLabel == String(format: "routine.detail.muscle_map.sets_count".localized, 8))
        #expect(performed?.stateLabel != planned?.stateLabel)
        #expect(planned?.stateLabel.contains("routine.detail") == false)
    }

    @Test("Spoken labels carry the distinction for lit and idle regions alike")
    func accessibilityLabelsArePhrasedByReading() {
        let performed = Self.model(.performed)
        let planned = Self.model(.planned)

        // A region the source leads.
        #expect(performed.accessibilityLabels[.chest] != planned.accessibilityLabels[.chest])
        #expect(planned.accessibilityLabels[.chest] == String(
            format: "routine.detail.muscle_map.a11y.belly_primary".localized,
            MuscleMapRegion.chest.displayName,
            8
        ))

        // A region it does not touch at all — "not trained" would be a claim about a plan.
        #expect(performed.accessibilityLabels[.calves] != planned.accessibilityLabels[.calves])
        #expect(planned.accessibilityLabels[.calves] == String(
            format: "routine.detail.muscle_map.a11y.belly_idle".localized,
            MuscleMapRegion.calves.displayName
        ))

        // The pre-joined summary quotes the per-region phrase, so it moves with the reading too.
        #expect(performed.accessibilitySummary != planned.accessibilitySummary)
    }

    // MARK: - Everything else stays shared

    @Test("Only the count-bearing strings differ — the picture and the shared copy do not")
    func readingsDifferOnlyInWording() {
        let performed = Self.model(.performed)
        let planned = Self.model(.planned)

        #expect(performed.highlights == planned.highlights)
        #expect(performed.pills == planned.pills)
        // Supporting work says "Sekundär" under either reading; there is no count to qualify.
        #expect(performed.details[.shoulders] == planned.details[.shoulders])
        #expect(performed.accessibilityLabels[.shoulders] == planned.accessibilityLabels[.shoulders])
    }

    @Test("A source that maps to nothing is empty under either reading, so the card hides")
    func emptySourceHidesTheCardUnderEitherReading() {
        for reading in [MuscleMapReading.performed, .planned] {
            let model = MuscleMapCardModel.make(from: [:], reading: reading)
            #expect(model.hasTraining == false)
            #expect(model.pills.isEmpty)
        }
    }
}
