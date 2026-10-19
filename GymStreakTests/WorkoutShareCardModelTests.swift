//
//  WorkoutShareCardModelTests.swift
//  GymStreakTests
//
//  `WorkoutShareCardModel.make(from:layers:weightUnit:)` decides everything the share card
//  shows: which records, in which unit, which layers survive the preview sheet's chips, and
//  where the callouts sit. See docs/workout-sharing.md.
//

import Foundation
import Testing
@testable import GymStreak

@MainActor
struct WorkoutShareCardModelTests {

    private static let loads: [MuscleMapRegion: MuscleLoad] = [
        .chest: MuscleLoad(engagement: .primary, setCount: 9, exerciseNames: ["Bench Press"]),
        .shoulders: MuscleLoad(engagement: .primary, setCount: 6, exerciseNames: ["Overhead Press"]),
        .triceps: MuscleLoad(engagement: .primary, setCount: 6, exerciseNames: ["Dips"]),
        .forearms: MuscleLoad(engagement: .secondary, setCount: 0, exerciseNames: ["Bench Press"]),
    ]

    private static func source(
        records: [WorkoutShareSource.Record] = [],
        exerciseNames: [String] = ["Bench Press", "Overhead Press", "Dips"],
        topSet: WorkoutShareSource.TopSet? = nil
    ) -> WorkoutShareSource {
        WorkoutShareSource(
            title: "Push Day",
            date: Date(timeIntervalSince1970: 1_760_800_000),
            duration: 72 * 60 + 40,
            completedSets: 24,
            volumeKg: 8_940,
            exerciseNames: exerciseNames,
            loads: loads,
            topSet: topSet,
            records: records
        )
    }

    private static let bench = WorkoutShareSource.Record(exerciseName: "Bench Press", region: .chest, weightKg: 100, reps: 5)
    private static let press = WorkoutShareSource.Record(exerciseName: "Overhead Press", region: .shoulders, weightKg: 62.5, reps: 5)
    private static let dips = WorkoutShareSource.Record(exerciseName: "Dips", region: .triceps, weightKg: 20, reps: 8)

    // MARK: - Records

    @Test("Records list each PR with its set, and tag the muscle it trained")
    func recordsAreListedAndTagged() {
        let model = WorkoutShareCardModel.make(
            from: Self.source(records: [Self.bench, Self.press]),
            layers: WorkoutShareLayers(),
            weightUnit: .kilograms
        )

        #expect(model.recordsLabel == "share_card.records_many".localized(2))
        #expect(model.records.map(\.exercise) == ["Bench Press", "Overhead Press"])
        #expect(model.records.first?.value == "share_card.weight_reps".localized(WeightFormatting.label(100, in: .kilograms), 5))
        let tagged = Set(model.callouts.filter(\.hasRecord).map(\.id))
        #expect(tagged == [.chest, .shoulders])
    }

    @Test("A workout without PRs has no records section and no PR tags")
    func noRecordsHidesTheSection() {
        let model = WorkoutShareCardModel.make(from: Self.source(), layers: WorkoutShareLayers(), weightUnit: .kilograms)

        #expect(model.recordsLabel == nil)
        #expect(model.records.isEmpty)
        #expect(model.callouts.allSatisfy { !$0.hasRecord })
        #expect(model.callouts.count == 3, "Only the three primary movers get a callout")
    }

    @Test("The label counts every record while the section shows at most two rows")
    func recordRowsAreCapped() {
        let model = WorkoutShareCardModel.make(
            from: Self.source(records: [Self.bench, Self.press, Self.dips]),
            layers: WorkoutShareLayers(),
            weightUnit: .kilograms
        )

        #expect(model.recordsLabel == "share_card.records_many".localized(3))
        #expect(model.records.count == WorkoutShareCardModel.maximumRecordRows)
    }

    // MARK: - Units and the Weights chip

    @Test("Pounds convert the volume and the record weights from kilograms")
    func poundsConvert() {
        let model = WorkoutShareCardModel.make(
            from: Self.source(records: [Self.bench]),
            layers: WorkoutShareLayers(),
            weightUnit: .pounds
        )

        let volume = model.stats[2]
        #expect(volume.unit == WeightFormatting.unitWord(.pounds))
        #expect(volume.value == WeightUnit.pounds.converting(fromKilograms: 8_940)
            .formatted(.number.precision(.fractionLength(0))))
        #expect(model.records.first?.value
            == "share_card.weight_reps".localized(WeightFormatting.label(100, in: .pounds), 5))
    }

    @Test("Weights off shows reps only and swaps volume for the exercise count")
    func weightsOffHidesNumbers() {
        var layers = WorkoutShareLayers()
        layers.weights = false
        let model = WorkoutShareCardModel.make(from: Self.source(records: [Self.bench]), layers: layers, weightUnit: .kilograms)

        #expect(model.records.first?.value == "set.reps".localized(5))
        #expect(model.stats[2].value == "3")
        #expect(model.stats[2].label == "share_card.stat.exercises".localized)
        #expect(model.stats[2].unit.isEmpty)
    }

    // MARK: - Layers

    @Test("Muscles off drops the callouts and grows the figures")
    func musclesOffGrowsFigures() {
        var layers = WorkoutShareLayers()
        layers.muscles = false
        let model = WorkoutShareCardModel.make(from: Self.source(), layers: layers, weightUnit: .kilograms)

        #expect(model.callouts.isEmpty)
        #expect(model.stage.figureWidth == 280)
        #expect(!model.highlights.isEmpty, "The figures still light up")
    }

    @Test("Stats and exercise line follow their chips")
    func statsAndExercisesFollowChips() {
        var layers = WorkoutShareLayers()
        layers.stats = false
        layers.exercises = true
        let model = WorkoutShareCardModel.make(from: Self.source(), layers: layers, weightUnit: .kilograms)

        #expect(model.stats.isEmpty)
        #expect(model.exerciseLine == "Bench Press  ·  Overhead Press  ·  Dips")
    }

    @Test("A one-exercise workout spells out its top set, or its set count without weights")
    func singleExerciseLine() {
        let source = Self.source(exerciseNames: ["Back Squat"], topSet: .init(weightKg: 140, reps: 3))
        var layers = WorkoutShareLayers()
        layers.exercises = true

        let withWeights = WorkoutShareCardModel.make(from: source, layers: layers, weightUnit: .kilograms)
        #expect(withWeights.exerciseLine == "share_card.single_top_set".localized(
            "Back Squat",
            "share_card.weight_reps".localized(WeightFormatting.label(140, in: .kilograms), 3)
        ))

        layers.weights = false
        let withoutWeights = WorkoutShareCardModel.make(from: source, layers: layers, weightUnit: .kilograms)
        #expect(withoutWeights.exerciseLine == "share_card.single_sets".localized("Back Squat", 24))
    }

    // MARK: - Chip availability

    @Test("The PRs chip is offered only when the workout set a record")
    func recordsChipNeedsRecords() {
        #expect(!WorkoutShareCardModel.make(from: Self.source(), layers: WorkoutShareLayers(), weightUnit: .kilograms).isRecordsChipShown)
        #expect(WorkoutShareCardModel.make(from: Self.source(records: [Self.bench]), layers: WorkoutShareLayers(), weightUnit: .kilograms).isRecordsChipShown)
    }

    @Test("The Weights chip is disabled while nothing it changes is visible")
    func weightsChipFollowsWhatItAffects() {
        var layers = WorkoutShareLayers()
        layers.stats = false
        layers.records = false
        let multi = Self.source(records: [Self.bench])
        #expect(!WorkoutShareCardModel.make(from: multi, layers: layers, weightUnit: .kilograms).isWeightsChipEnabled)

        layers.exercises = true
        #expect(!WorkoutShareCardModel.make(from: multi, layers: layers, weightUnit: .kilograms).isWeightsChipEnabled,
                "A multi-exercise line carries no weights")
        let single = Self.source(exerciseNames: ["Back Squat"], topSet: .init(weightKg: 140, reps: 3))
        #expect(WorkoutShareCardModel.make(from: single, layers: layers, weightUnit: .kilograms).isWeightsChipEnabled)

        layers.exercises = false
        layers.records = true
        #expect(WorkoutShareCardModel.make(from: multi, layers: layers, weightUnit: .kilograms).isWeightsChipEnabled)
        #expect(!WorkoutShareCardModel.make(from: Self.source(), layers: layers, weightUnit: .kilograms).isWeightsChipEnabled,
                "PRs on but no records to show")
    }

    // MARK: - Callout layout

    @Test("Front-only muscles label left, back-only right, and labels in a column never overlap")
    func calloutsSplitAndDoNotOverlap() {
        let stage = WorkoutShareCalloutLayout.stage(showsCallouts: true)
        let callouts = WorkoutShareCalloutLayout.callouts(
            for: [.chest, .biceps, .abs, .back, .triceps, .shoulders, .forearms],
            in: stage
        )

        #expect(callouts.count == 7)
        let left = callouts.filter(\.isLeftColumn)
        let right = callouts.filter { !$0.isLeftColumn }
        #expect(Set([.chest, .biceps, .abs]).isSubset(of: Set(left.map(\.region))))
        #expect(Set([.back, .triceps]).isSubset(of: Set(right.map(\.region))))
        for column in [left, right] {
            let tops = column.map(\.labelOrigin.y).sorted()
            for (upper, lower) in zip(tops, tops.dropFirst()) {
                #expect(lower - upper >= 124, "84 pt label + 40 pt gap")
            }
            #expect((tops.first ?? 0) >= 0)
        }
    }
}
