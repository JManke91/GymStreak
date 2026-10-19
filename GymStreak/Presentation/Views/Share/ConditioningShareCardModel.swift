//
//  ConditioningShareCardModel.swift
//  GymStreak
//
//  The finished values the conditioning share card renders: localized, formatted and
//  laid out ahead of time, so the card's body only reads properties. Design:
//  `ConditioningCard.dc.html` (docs/workout-sharing.md).
//

import CoreGraphics
import Foundation

/// What a conditioning record contributes to its share card, read once from the record.
struct ConditioningShareSource: Equatable {
    let title: String
    let date: Date
    let duration: TimeInterval
    let modality: ConditioningModality?
    let effort: ConditioningEffort?
    let roundsCompleted: Int
    /// 0 for steady state.
    let roundsPlanned: Int
    let workInterval: TimeInterval
    let restInterval: TimeInterval
    /// Nil until read from Apple Health, and for good when there is none.
    var heartRate: ConditioningHeartRateSummary?

    var isSteadyState: Bool { roundsPlanned == 0 }
}

/// The preview sheet's chips for a conditioning card.
struct ConditioningShareLayers: Equatable {
    var rounds = true
    var heartRate = true
    var stats = true
}

struct ConditioningShareCardModel: Equatable {

    struct Block: Equatable, Identifiable {
        enum Kind: Equatable { case work, missedWork, rest }
        let id: Int
        let kind: Kind
        let width: CGFloat
        let label: String?
    }

    struct Legend: Equatable {
        let work: String
        let rest: String
    }

    struct Zone: Equatable, Identifiable {
        /// 0 is Z1.
        let id: Int
        let name: String
        /// Bar length relative to the longest zone, 0...1.
        let fraction: Double
        let time: String
    }

    let eyebrow: String
    let title: String
    let subtitle: String
    /// Nil hides the round strip.
    let stripHeading: String?
    let stripValue: String
    let blocks: [Block]
    /// `blockGap`, or `denseBlockGap` when a long session would not fit otherwise.
    let blockSpacing: CGFloat
    let stripHeight: CGFloat
    /// Nil for steady state, which has no work/rest split to explain.
    let legend: Legend?
    /// Z5 first; empty hides the zone card.
    let zones: [Zone]
    /// Empty hides the stats row.
    let stats: [WorkoutShareCardModel.Stat]
    let wordmark: String
    let tagline: String
    /// The Heart rate chip is offered only when the session has heart-rate data.
    let isHeartRateChipShown: Bool

    /// The card's content width: 1080 minus the 80-point side margins.
    static let stripWidth: CGFloat = 920
    static let blockGap: CGFloat = 8
    static let denseBlockGap: CGFloat = 4
    /// An 8 s sprint beside 90 s of rest would otherwise be a hairline.
    static let minimumBlockWidth: CGFloat = 16
    /// "R12" at 24 pt needs this much; narrower blocks stay unlabelled.
    static let minimumLabelWidth: CGFloat = 52

    /// Call when the source or a layer changes, never from a view body.
    static func make(
        from source: ConditioningShareSource,
        layers: ConditioningShareLayers,
        wordmark: String = AppBrand.wordmark
    ) -> ConditioningShareCardModel {
        let heartRate = layers.heartRate ? source.heartRate : nil
        let zones = heartRate?.zoneSeconds.map(zoneRows) ?? []
        // Without the zone card the strip is the only visual, so it grows and names each round.
        let isBigStrip = zones.isEmpty

        var subtitle = [source.modality.map(ConditioningCopy.modality), structure(of: source)].compactMap { $0 }
        if heartRate == nil, let effort = source.effort {
            subtitle.append("share_card.conditioning.effort.\(effort.rawValue)".localized)
        }

        return ConditioningShareCardModel(
            eyebrow: [
                source.date.formatted(weekdayStyle),
                source.date.formatted(dayMonthStyle),
                "share_card.conditioning.kind".localized
            ].joined(separator: " · "),
            title: source.title,
            subtitle: subtitle.joined(separator: " · "),
            stripHeading: layers.rounds
                ? (source.isSteadyState ? "share_card.conditioning.steady" : "share_card.conditioning.rounds").localized
                : nil,
            // Steady state: the duration stat already says it.
            stripValue: source.isSteadyState ? "" : "\(source.roundsCompleted) / \(source.roundsPlanned)",
            blocks: layers.rounds ? blocks(for: source, labelled: isBigStrip) : [],
            blockSpacing: blockSpacing(count: blockCount(source)),
            stripHeight: isBigStrip ? 200 : 96,
            legend: source.isSteadyState ? nil : Legend(
                work: "share_card.conditioning.work_legend".localized(clock(source.workInterval)),
                rest: "share_card.conditioning.rest_legend".localized(clock(source.restInterval))
            ),
            zones: zones,
            stats: layers.stats ? stats(for: source, heartRate: heartRate) : [],
            wordmark: wordmark,
            tagline: "share_card.tagline".localized,
            isHeartRateChipShown: source.heartRate != nil
        )
    }

    // MARK: - Private

    private static let weekdayStyle = Date.FormatStyle().weekday(.wide)
    private static let dayMonthStyle = Date.FormatStyle().day().month(.abbreviated)

    private static func clock(_ seconds: TimeInterval) -> String {
        ConditioningCopy.clock(seconds.rounded(.down))
    }

    /// "8 × 2:00 work, 1:00 rest" or, for steady state, "45 min".
    private static func structure(of source: ConditioningShareSource) -> String {
        if source.isSteadyState {
            return "conditioning.unit.minutes".localized(Int(source.duration / 60))
        }
        return "share_card.conditioning.structure".localized(
            source.roundsPlanned, clock(source.workInterval), clock(source.restInterval)
        )
    }

    /// Work blocks green (faded when the session ended before them), rest grey, widths
    /// proportional to time. Steady state is one block.
    private static func blocks(for source: ConditioningShareSource, labelled: Bool) -> [Block] {
        guard !source.isSteadyState else {
            return [Block(id: 0, kind: .work, width: stripWidth, label: nil)]
        }
        var kinds: [(kind: Block.Kind, seconds: TimeInterval, round: Int?)] = []
        for round in 0..<source.roundsPlanned {
            kinds.append((round < source.roundsCompleted ? .work : .missedWork, source.workInterval, round + 1))
            if round < source.roundsPlanned - 1 {
                kinds.append((.rest, source.restInterval, nil))
            }
        }
        let total = stripWidth - blockSpacing(count: kinds.count) * CGFloat(kinds.count - 1)
        // A 30-round session cannot give every block the full minimum; share the width evenly then.
        let minimum = min(minimumBlockWidth, total / CGFloat(kinds.count))
        let widths = proportionalWidths(kinds.map(\.seconds), total: total, minimum: minimum)
        return kinds.enumerated().map { index, item in
            let width = widths[index]
            let label = labelled && width >= minimumLabelWidth
                ? item.round.map { "share_card.conditioning.round_label".localized($0) }
                : nil
            return Block(id: index, kind: item.kind, width: width, label: label)
        }
    }

    private static func blockCount(_ source: ConditioningShareSource) -> Int {
        source.isSteadyState ? 1 : 2 * source.roundsPlanned - 1
    }

    /// Long sessions (from 20 rounds at the full gap and minimum width) tighten the gap.
    private static func blockSpacing(count: Int) -> CGFloat {
        let fits = minimumBlockWidth * CGFloat(count) + blockGap * CGFloat(max(0, count - 1)) <= stripWidth
        return fits ? blockGap : denseBlockGap
    }

    /// Widths proportional to `weights` summing to `total`, none below `minimum`:
    /// blocks that would fall below it are pinned there and the rest share what is left.
    private static func proportionalWidths(_ weights: [TimeInterval], total: CGFloat, minimum: CGFloat) -> [CGFloat] {
        var pinned = Set<Int>()
        while true {
            let free = total - minimum * CGFloat(pinned.count)
            let freeWeight = weights.indices.filter { !pinned.contains($0) }.reduce(0) { $0 + weights[$1] }
            let widths = weights.indices.map { index -> CGFloat in
                guard !pinned.contains(index) else { return minimum }
                return freeWeight > 0 ? free * CGFloat(weights[index] / freeWeight) : free / CGFloat(weights.count)
            }
            let newlyPinned = weights.indices.filter { !pinned.contains($0) && widths[$0] < minimum }
            if newlyPinned.isEmpty { return widths }
            pinned.formUnion(newlyPinned)
        }
    }

    private static func zoneRows(_ seconds: [TimeInterval]) -> [Zone] {
        let longest = seconds.max() ?? 0
        return seconds.indices.reversed().map { index in
            Zone(
                id: index,
                name: "share_card.conditioning.zone".localized(index + 1),
                fraction: longest > 0 ? seconds[index] / longest : 0,
                time: clock(seconds[index])
            )
        }
    }

    /// With heart rate: duration, average and maximum. Without: duration, work and rest —
    /// or only the duration for steady state, which has no work/rest split.
    private static func stats(
        for source: ConditioningShareSource,
        heartRate: ConditioningHeartRateSummary?
    ) -> [WorkoutShareCardModel.Stat] {
        let duration = WorkoutShareCardModel.Stat(
            id: 0, value: clock(source.duration), unit: "", label: "share_card.stat.duration".localized
        )
        if let heartRate {
            let bpm = "share_card.unit.bpm".localized
            return [
                duration,
                .init(id: 1, value: "\(heartRate.averageBPM)", unit: bpm, label: "share_card.stat.avg_hr".localized),
                .init(id: 2, value: "\(heartRate.maxBPM)", unit: bpm, label: "share_card.stat.max_hr".localized)
            ]
        }
        guard !source.isSteadyState else { return [duration] }
        let work = source.workInterval * Double(source.roundsCompleted)
        let rest = source.restInterval * Double(max(0, source.roundsCompleted - 1))
        return [
            duration,
            .init(id: 1, value: clock(work), unit: "", label: "share_card.stat.work".localized),
            .init(id: 2, value: clock(rest), unit: "", label: "share_card.stat.rest".localized)
        ]
    }
}
