//
//  WorkoutShareCardModel.swift
//  GymStreak
//
//  The finished values the strength share card renders: everything localized, laid out and
//  formatted ahead of time, so the card's body only reads properties. See
//  docs/workout-sharing.md.
//

import Foundation

/// What a workout contributes to its share card, read once from the session.
///
/// Plain values: the card is built from this and never from a `@Model`, so building it can
/// happen anywhere and the builder is testable without SwiftData.
struct WorkoutShareSource: Equatable {

    struct Record: Equatable {
        let exerciseName: String
        /// The muscle the record's exercise trains first — where the card tags it.
        let region: MuscleMapRegion?
        let weightKg: Double
        let reps: Int
    }

    struct TopSet: Equatable {
        let weightKg: Double
        let reps: Int
    }

    let title: String
    let date: Date
    let duration: TimeInterval
    let completedSets: Int
    let volumeKg: Double
    /// Exercises with at least one completed set, in workout order.
    let exerciseNames: [String]
    let loads: [MuscleMapRegion: MuscleLoad]
    /// The best set of a one-exercise workout, which its exercise line spells out.
    let topSet: TopSet?
    /// New personal records, in workout order. Empty until the history check returns.
    var records: [Record] = []
}

/// The five things a user can switch off before sharing — the preview sheet's chips.
struct WorkoutShareLayers: Equatable {
    var muscles = true
    var records = true
    var stats = true
    var exercises = false
    var weights = true
}

struct WorkoutShareCardModel: Equatable {

    struct Callout: Equatable, Identifiable {
        let placement: WorkoutShareCalloutLayout.Callout
        let name: String
        let sets: String
        let hasRecord: Bool

        var id: MuscleMapRegion { placement.region }
    }

    struct RecordRow: Equatable, Identifiable {
        let id: Int
        let exercise: String
        let value: String
    }

    struct Stat: Equatable, Identifiable {
        let id: Int
        let value: String
        let unit: String
        let label: String
    }

    let dateLine: String
    let title: String
    let highlights: [MuscleMapRegion: MuscleEngagement]
    let stage: WorkoutShareCalloutLayout.Stage
    let callouts: [Callout]
    /// Nil hides the Personal records section.
    let recordsLabel: String?
    let records: [RecordRow]
    /// Empty hides the stats row.
    let stats: [Stat]
    /// Nil hides the exercise line.
    let exerciseLine: String?
    let wordmark: String
    let tagline: String
    /// The PRs chip is offered only when the workout set a record — otherwise it toggles nothing.
    let isRecordsChipShown: Bool
    /// The Weights chip only changes the volume stat, the record values and a one-exercise line;
    /// with all three hidden it changes nothing, so it is disabled (its setting is kept).
    let isWeightsChipEnabled: Bool

    /// The section fits two rows above the stats inside the story-safe area; the design
    /// shows at most two, and the label still counts every record.
    static let maximumRecordRows = 2

    /// Call when the source or a layer changes, never from a view body.
    static func make(
        from source: WorkoutShareSource,
        layers: WorkoutShareLayers,
        weightUnit: WeightUnit,
        wordmark: String = AppBrand.wordmark
    ) -> WorkoutShareCardModel {
        let stage = WorkoutShareCalloutLayout.stage(showsCallouts: layers.muscles)
        let recordRegions = Set(source.records.compactMap(\.region))

        // Only primary movers get a label, heaviest first; secondary ones read from the fill.
        let primaries = MuscleMapRegion.allCases
            .compactMap { region in source.loads[region].map { (region, $0) } }
            .filter { $0.1.engagement == .primary }
            .sorted { $0.1.setCount > $1.1.setCount }
        let callouts = layers.muscles
            ? WorkoutShareCalloutLayout.callouts(for: primaries.map(\.0), in: stage).map { placement in
                Callout(
                    placement: placement,
                    name: calloutName(for: placement.region),
                    sets: "share_card.callout_sets".localized(source.loads[placement.region]?.setCount ?? 0),
                    hasRecord: layers.records && recordRegions.contains(placement.region)
                )
            }
            : []

        let showsRecords = layers.records && !source.records.isEmpty
        let records = showsRecords
            ? source.records.prefix(maximumRecordRows).enumerated().map { index, record in
                RecordRow(
                    id: index,
                    exercise: record.exerciseName,
                    value: layers.weights
                        ? setLabel(weightKg: record.weightKg, reps: record.reps, unit: weightUnit)
                        : "set.reps".localized(record.reps)
                )
            }
            : []

        return WorkoutShareCardModel(
            dateLine: "\(source.date.formatted(weekdayStyle)) · \(source.date.formatted(dayMonthStyle))",
            title: source.title.isEmpty ? "share_card.untitled".localized : source.title,
            highlights: source.loads.mapValues(\.engagement),
            stage: stage,
            callouts: callouts,
            recordsLabel: showsRecords ? recordsLabel(count: source.records.count) : nil,
            records: records,
            stats: layers.stats ? stats(for: source, showsWeights: layers.weights, unit: weightUnit) : [],
            exerciseLine: layers.exercises ? exerciseLine(for: source, showsWeights: layers.weights, unit: weightUnit) : nil,
            wordmark: wordmark,
            tagline: "share_card.tagline".localized,
            isRecordsChipShown: !source.records.isEmpty,
            isWeightsChipEnabled: layers.stats || showsRecords
                || (layers.exercises && source.exerciseNames.count == 1 && source.topSet != nil)
        )
    }

    // MARK: - Private

    private static let weekdayStyle = Date.FormatStyle().weekday(.wide)
    private static let dayMonthStyle = Date.FormatStyle().day().month(.abbreviated)
    private static let groupedStyle = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))

    /// The design's short gym names where they differ from the figure's region names.
    private static func calloutName(for region: MuscleMapRegion) -> String {
        switch region {
        case .back: "share_card.region.back".localized
        case .quadriceps: "share_card.region.quadriceps".localized
        case .trapezius: "share_card.region.trapezius".localized
        default: region.displayName
        }
    }

    private static func recordsLabel(count: Int) -> String {
        count == 1 ? "share_card.records_one".localized : "share_card.records_many".localized(count)
    }

    private static func setLabel(weightKg: Double, reps: Int, unit: WeightUnit) -> String {
        "share_card.weight_reps".localized(WeightFormatting.label(weightKg, in: unit), reps)
    }

    private static func stats(for source: WorkoutShareSource, showsWeights: Bool, unit: WeightUnit) -> [Stat] {
        let third: Stat
        if showsWeights {
            // Whole display units with grouping ("8,940 kg"), never rolled up to tonnes.
            third = Stat(
                id: 2,
                value: unit.converting(fromKilograms: source.volumeKg).formatted(groupedStyle),
                unit: WeightFormatting.unitWord(unit),
                label: "share_card.stat.volume".localized
            )
        } else {
            let count = source.exerciseNames.count
            third = Stat(
                id: 2,
                value: "\(count)",
                unit: "",
                label: count == 1 ? "share_card.stat.exercise".localized : "share_card.stat.exercises".localized
            )
        }
        return [
            Stat(
                id: 0,
                value: "\(Int(source.duration / 60))",
                unit: "share_card.unit.minutes".localized,
                label: "share_card.stat.duration".localized
            ),
            Stat(id: 1, value: "\(source.completedSets)", unit: "", label: "share_card.stat.sets".localized),
            third
        ]
    }

    private static func exerciseLine(for source: WorkoutShareSource, showsWeights: Bool, unit: WeightUnit) -> String {
        guard source.exerciseNames.count == 1, let name = source.exerciseNames.first else {
            return source.exerciseNames.joined(separator: "  ·  ")
        }
        if showsWeights, let top = source.topSet {
            return "share_card.single_top_set".localized(name, setLabel(weightKg: top.weightKg, reps: top.reps, unit: unit))
        }
        return "share_card.single_sets".localized(name, source.completedSets)
    }
}
