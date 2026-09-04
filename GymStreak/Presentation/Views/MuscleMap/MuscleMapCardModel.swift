//
//  MuscleMapCardModel.swift
//  GymStreak
//
//  The finished values `MuscleMapCardView` renders: everything localized, ordered and
//  joined ahead of time so the card's body only ever does dictionary lookups.
//

import Foundation

/// Which question a map answers. One card, two readings: a recorded workout states what *was*
/// trained, a routine what it *plans* to train. Only the wording differs — and only the wording
/// that names the card itself or a set count. The legend, the figure captions, "secondary" and the
/// reset control say the same thing about both, so they stay on the shared `history.*` set.
enum MuscleMapReading {
    /// A recorded workout — "Trained Muscle Groups", "12 sets".
    case performed
    /// A routine — "Planned Muscle Groups", "12 sets planned".
    case planned

    fileprivate struct Keys {
        let title: String
        let setsCount: String
        let regionSets: String
        let bellyPrimary: String
        let bellyIdle: String
    }

    fileprivate var keys: Keys {
        switch self {
        case .performed:
            Keys(
                title: "history.detail.muscle_map.title",
                setsCount: "history.detail.muscle_map.sets_count",
                regionSets: "history.detail.muscle_map.a11y.region_sets",
                bellyPrimary: "history.detail.muscle_map.a11y.belly_primary",
                bellyIdle: "history.detail.muscle_map.a11y.belly_untrained"
            )
        case .planned:
            Keys(
                title: "routine.detail.muscle_map.title",
                setsCount: "routine.detail.muscle_map.sets_count",
                regionSets: "routine.detail.muscle_map.a11y.region_sets",
                bellyPrimary: "routine.detail.muscle_map.a11y.belly_primary",
                bellyIdle: "routine.detail.muscle_map.a11y.belly_idle"
            )
        }
    }
}

/// One trained region as the card lists it beneath the figures.
struct MuscleMapPill: Identifiable, Equatable {
    let region: MuscleMapRegion
    let name: String
    let engagement: MuscleEngagement
    /// Sets of the exercises this region led, shown only on primary pills — supporting work
    /// carries no count.
    let setCount: Int

    var id: MuscleMapRegion { region }
}

/// What the detail chip shows while a region is selected.
struct MuscleMapDetail: Equatable {
    let name: String
    /// "8 sets" (or "8 sets planned" on a routine) for a primary region, "Secondary" for a
    /// supporting one.
    let stateLabel: String
    /// The exercises that trained the region, pre-joined ("Bench Press · Dips").
    let exercises: String
}

/// Everything the muscle map card draws, built once off the render path.
///
/// The card takes this finished value rather than a `WorkoutSession` or a `Routine`: the
/// aggregation walks SwiftData relationships, which must never happen while a body is being
/// evaluated. The reading is baked in here too, so the card renders whichever one it is handed
/// without knowing which screen it is on.
struct MuscleMapCardModel: Equatable {

    static let empty = MuscleMapCardModel(
        title: "",
        highlights: [:],
        pills: [],
        details: [:],
        accessibilityLabels: [:],
        accessibilitySummary: ""
    )

    /// The card's own heading — "Trained Muscle Groups" or "Planned Muscle Groups".
    let title: String
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

    /// False when the source mapped to no region at all; the card then draws nothing.
    var hasTraining: Bool { !highlights.isEmpty }

    /// Call once when the screen loads (or when its source changes), never from a view body.
    static func make(from loads: [MuscleMapRegion: MuscleLoad], reading: MuscleMapReading) -> MuscleMapCardModel {
        guard !loads.isEmpty else { return .empty }
        let keys = reading.keys

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
            .sorted { $0.setCount > $1.setCount }
        let pills = primaryPills + secondaryRegions.map { pill(for: $0, load: loads[$0]!) }

        var parts: [String] = []
        if !primaryRegions.isEmpty {
            let spoken = primaryPills
                .map { String(format: keys.regionSets.localized, $0.name, $0.setCount) }
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
                labels[region] = String(format: keys.bellyIdle.localized, region.displayName)
                continue
            }
            let isPrimary = load.engagement == .primary
            details[region] = MuscleMapDetail(
                name: region.displayName,
                stateLabel: isPrimary
                    ? String(format: keys.setsCount.localized, load.setCount)
                    : "history.detail.muscle_map.secondary".localized,
                exercises: load.exerciseNames.joined(separator: " · ")
            )
            labels[region] = isPrimary
                ? String(format: keys.bellyPrimary.localized, region.displayName, load.setCount)
                : String(
                    format: "history.detail.muscle_map.a11y.belly_secondary".localized,
                    region.displayName
                )
        }

        return MuscleMapCardModel(
            title: keys.title.localized,
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
            setCount: load.setCount
        )
    }
}
