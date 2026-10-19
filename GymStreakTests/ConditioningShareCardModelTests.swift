//
//  ConditioningShareCardModelTests.swift
//  GymStreakTests
//
//  The conditioning share card's content: heart-rate and no-heart-rate states, the round
//  strip, steady state and the layer chips. See docs/workout-sharing.md.
//

import CoreGraphics
import Foundation
import Testing
@testable import GymStreak

struct ConditioningShareCardModelTests {

    private func source(
        rounds: Int = 8,
        completed: Int = 8,
        work: TimeInterval = 120,
        rest: TimeInterval = 60,
        heartRate: ConditioningHeartRateSummary? = nil
    ) -> ConditioningShareSource {
        ConditioningShareSource(
            title: "Lactic 30/120",
            date: Date(timeIntervalSinceReferenceDate: 0),
            duration: 1380,
            modality: .assaultBike,
            effort: .hardRepeatable,
            roundsCompleted: completed,
            roundsPlanned: rounds,
            workInterval: work,
            restInterval: rest,
            heartRate: heartRate
        )
    }

    private let heartRate = ConditioningHeartRateSummary(
        averageBPM: 164, maxBPM: 189, zoneSeconds: [20, 210, 380, 580, 190]
    )

    @Test
    func heartRateStateShowsZonesFiveFirstAndHeartRateStats() {
        let card = ConditioningShareCardModel.make(from: source(heartRate: heartRate), layers: .init())
        #expect(card.zones.map(\.id) == [4, 3, 2, 1, 0])
        #expect(card.zones.first { $0.id == 3 }?.fraction == 1)
        #expect(card.stats.map(\.value) == ["23:00", "164", "189"])
        #expect(card.stripHeight == 96)
        #expect(card.blocks.allSatisfy { $0.label == nil })
        #expect(card.isHeartRateChipShown)
        #expect(!card.subtitle.contains("share_card.conditioning.effort.hardRepeatable".localized))
    }

    @Test
    func noHeartRateStateGrowsTheStripAndShowsWorkAndRest() {
        let card = ConditioningShareCardModel.make(from: source(), layers: .init())
        #expect(card.zones.isEmpty)
        #expect(card.stripHeight == 200)
        #expect(card.blocks.first?.label == "share_card.conditioning.round_label".localized(1))
        #expect(card.stats.map(\.value) == ["23:00", "16:00", "7:00"])
        #expect(card.subtitle.contains("share_card.conditioning.effort.hardRepeatable".localized))
        #expect(!card.isHeartRateChipShown)
    }

    @Test
    func heartRateChipOffHidesZonesButKeepsTheChip() {
        var layers = ConditioningShareLayers()
        layers.heartRate = false
        let card = ConditioningShareCardModel.make(from: source(heartRate: heartRate), layers: layers)
        #expect(card.zones.isEmpty)
        #expect(card.stats.map(\.label).contains("share_card.stat.work".localized))
        #expect(card.isHeartRateChipShown)
    }

    @Test
    func averageAndMaxWithoutZonesWhenThereIsNoProfile() {
        let summary = ConditioningHeartRateSummary(averageBPM: 150, maxBPM: 180, zoneSeconds: nil)
        let card = ConditioningShareCardModel.make(from: source(heartRate: summary), layers: .init())
        #expect(card.zones.isEmpty)
        #expect(card.stats.map(\.value) == ["23:00", "150", "180"])
    }

    @Test
    func stripFillsTheWidthWithRoundsMissedWhenEndedEarly() {
        let card = ConditioningShareCardModel.make(from: source(rounds: 6, completed: 4), layers: .init())
        #expect(card.blocks.count == 11)
        #expect(card.blocks.filter { $0.kind == .work }.count == 4)
        #expect(card.blocks.filter { $0.kind == .missedWork }.count == 2)
        #expect(card.stripValue == "4 / 6")
        let total = card.blocks.reduce(0) { $0 + $1.width } + card.blockSpacing * 10
        #expect(abs(total - ConditioningShareCardModel.stripWidth) < 0.5)
    }

    @Test
    func shortSprintsKeepAMinimumWidthAndLoseTheirLabel() {
        // Alactic: 15 × 8 s work, 90 s rest.
        let card = ConditioningShareCardModel.make(from: source(rounds: 15, completed: 15, work: 8, rest: 90), layers: .init())
        let work = card.blocks.filter { $0.kind == .work }
        #expect(work.allSatisfy { $0.width >= ConditioningShareCardModel.minimumBlockWidth })
        #expect(work.allSatisfy { $0.label == nil })
        let total = card.blocks.reduce(0) { $0 + $1.width } + card.blockSpacing * CGFloat(card.blocks.count - 1)
        #expect(abs(total - ConditioningShareCardModel.stripWidth) < 0.5)
    }

    @Test
    func thirtyRoundsStillFitTheStrip() {
        let card = ConditioningShareCardModel.make(from: source(rounds: 30, completed: 30, work: 10, rest: 60), layers: .init())
        #expect(card.blocks.count == 59)
        #expect(card.blockSpacing == ConditioningShareCardModel.denseBlockGap)
        let total = card.blocks.reduce(0) { $0 + $1.width } + card.blockSpacing * 58
        #expect(abs(total - ConditioningShareCardModel.stripWidth) < 0.5)
        #expect(card.blocks.allSatisfy { $0.width > 0 })
    }

    @Test
    func steadyStateIsOneBlockWithoutLegendAndOnlyDuration() {
        let card = ConditioningShareCardModel.make(from: source(rounds: 0, completed: 0, work: 0, rest: 0), layers: .init())
        #expect(card.blocks.count == 1)
        #expect(card.legend == nil)
        #expect(card.stripHeading == "share_card.conditioning.steady".localized)
        #expect(card.stats.count == 1)
    }

    @Test
    func roundsAndStatsLayersHideTheirSections() {
        let card = ConditioningShareCardModel.make(
            from: source(),
            layers: ConditioningShareLayers(rounds: false, heartRate: true, stats: false)
        )
        #expect(card.stripHeading == nil)
        #expect(card.blocks.isEmpty)
        #expect(card.stats.isEmpty)
    }
}
