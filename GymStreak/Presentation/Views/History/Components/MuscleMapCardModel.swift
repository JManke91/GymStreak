//
//  MuscleMapCardModel.swift
//  GymStreak
//
//  The finished values `MuscleMapCardView` renders: everything localized, ordered and
//  joined ahead of time so the card's body only ever does dictionary lookups.
//

import Foundation

/// One trained region as the card lists it beneath the figures.
struct MuscleMapPill: Identifiable, Equatable {
    let region: MuscleMapRegion
    let name: String
    let engagement: MuscleEngagement
    /// Completed sets, shown only on primary pills — supporting work carries no count.
    let completedSets: Int

    var id: MuscleMapRegion { region }
}

/// What the detail chip shows while a region is selected.
struct MuscleMapDetail: Equatable {
    let name: String
    /// "8 sets" for a primary region, "Secondary" for a supporting one.
    let stateLabel: String
    /// The exercises that trained the region, pre-joined ("Bench Press · Dips").
    let exercises: String
}

/// Everything the muscle map card draws, built once off the render path.
///
/// The card takes this finished value rather than a `WorkoutSession`: the aggregation walks
/// SwiftData relationships, which must never happen while a body is being evaluated.
struct MuscleMapCardModel: Equatable {

    static let empty = MuscleMapCardModel(
        highlights: [:],
        pills: [],
        details: [:],
        accessibilityLabels: [:],
        accessibilitySummary: ""
    )

    /// Regions to light up; anything absent renders in the idle grey.
    let highlights: [MuscleMapRegion: MuscleEngagement]
    /// The trained regions in display order: primary first, heaviest set count leading.
    let pills: [MuscleMapPill]
    /// Detail chip content per trained region, keyed so selecting one is a lookup rather
    /// than a scan in `body`.
    let details: [MuscleMapRegion: MuscleMapDetail]
    /// Spoken label per region — every region, trained or not, since the figures expose the
    /// untrained bellies too. Pre-built: formatting 13 localized strings belongs off `body`.
    let accessibilityLabels: [MuscleMapRegion: String]
    /// Pre-joined VoiceOver value — assembling it per render would be a collection reduction in `body`.
    let accessibilitySummary: String

    /// False when the workout mapped to no region at all; the card then draws nothing.
    var hasTraining: Bool { !highlights.isEmpty }

    /// Call once when the detail screen loads, never from a view body.
    static func make(from loads: [MuscleMapRegion: MuscleLoad]) -> MuscleMapCardModel {
        guard !loads.isEmpty else { return .empty }

        // Anatomical top-to-bottom order, so ties and the spoken summary read the same way
        // every time regardless of dictionary iteration order.
        func regions(_ engagement: MuscleEngagement) -> [MuscleMapRegion] {
            MuscleMapRegion.allCases.filter { loads[$0]?.engagement == engagement }
        }

        let primaryRegions = regions(.primary)
        let secondaryRegions = regions(.secondary)

        // The design leads with the region the workout hit hardest.
        let primaryPills = primaryRegions
            .map { pill(for: $0, load: loads[$0]!) }
            .sorted { $0.completedSets > $1.completedSets }
        let pills = primaryPills + secondaryRegions.map { pill(for: $0, load: loads[$0]!) }

        var parts: [String] = []
        if !primaryRegions.isEmpty {
            let spoken = primaryPills
                .map { String(format: "history.detail.muscle_map.a11y.region_sets".localized, $0.name, $0.completedSets) }
                .joined(separator: ", ")
            parts.append(String(format: "history.detail.muscle_map.a11y.primary".localized, spoken))
        }
        if !secondaryRegions.isEmpty {
            let spoken = secondaryRegions.map(\.displayName).joined(separator: ", ")
            parts.append(String(format: "history.detail.muscle_map.a11y.secondary".localized, spoken))
        }

        var details: [MuscleMapRegion: MuscleMapDetail] = [:]
        var labels: [MuscleMapRegion: String] = [:]
        for region in MuscleMapRegion.allCases {
            guard let load = loads[region] else {
                labels[region] = String(
                    format: "history.detail.muscle_map.a11y.belly_untrained".localized,
                    region.displayName
                )
                continue
            }
            let isPrimary = load.engagement == .primary
            details[region] = MuscleMapDetail(
                name: region.displayName,
                stateLabel: isPrimary
                    ? String(format: "history.detail.muscle_map.sets_count".localized, load.completedSets)
                    : "history.detail.muscle_map.secondary".localized,
                exercises: load.exerciseNames.joined(separator: " · ")
            )
            labels[region] = isPrimary
                ? String(
                    format: "history.detail.muscle_map.a11y.belly_primary".localized,
                    region.displayName,
                    load.completedSets
                )
                : String(
                    format: "history.detail.muscle_map.a11y.belly_secondary".localized,
                    region.displayName
                )
        }

        return MuscleMapCardModel(
            highlights: loads.mapValues(\.engagement),
            pills: pills,
            details: details,
            accessibilityLabels: labels,
            accessibilitySummary: parts.joined(separator: ". ")
        )
    }

    private static func pill(for region: MuscleMapRegion, load: MuscleLoad) -> MuscleMapPill {
        MuscleMapPill(
            region: region,
            name: region.displayName,
            engagement: load.engagement,
            completedSets: load.completedSets
        )
    }
}
