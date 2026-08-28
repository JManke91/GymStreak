//
//  ProgressiveOverloadServiceTests.swift
//  GymStreakWatchTests
//
//  Watch-side twin of `GymStreakTests/ProgressiveOverloadServiceTests.swift`.
//
//  The watch copy of `ProgressiveOverloadService` exists because the watch may
//  not import iOS `Domain/` (SwiftData). Its own header used to state that
//  "unit coverage lives against the iOS original … there is no watch unit-test
//  target" — that is what this file closes. The qualify/apply rules must stay
//  identical across the two copies, otherwise a suggestion shown on the watch
//  disagrees with the one iOS would have computed, so the assertions are kept
//  character-identical to the iOS twin on purpose.
//

import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct ProgressiveOverloadServiceTests {

    private func completedSets(reps: [Int]) -> [ProgressiveOverloadService.SetProgress] {
        reps.map { .init(reps: $0, isCompleted: true) }
    }

    // MARK: - Qualify (workout)

    @Test
    func allCompletedSetsAtMaxQualify() {
        #expect(ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: completedSets(reps: [12, 12, 12]),
            targetRepMax: 12
        ))
    }

    @Test
    func repsAboveMaxQualify() {
        #expect(ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: completedSets(reps: [13, 15, 12]),
            targetRepMax: 12
        ))
    }

    @Test
    func oneSetBelowMaxDisqualifies() {
        #expect(!ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: completedSets(reps: [12, 11, 12]),
            targetRepMax: 12
        ))
    }

    @Test
    func incompleteSetDisqualifiesEvenAtMaxReps() {
        var sets = completedSets(reps: [12, 12])
        sets.append(.init(reps: 12, isCompleted: false))
        #expect(!ProgressiveOverloadService.workoutQualifiesForIncrease(sets: sets, targetRepMax: 12))
    }

    @Test
    func noRepRangeGoalDisqualifies() {
        #expect(!ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: completedSets(reps: [12, 12]),
            targetRepMax: nil
        ))
    }

    @Test
    func noSetsDisqualify() {
        #expect(!ProgressiveOverloadService.workoutQualifiesForIncrease(sets: [], targetRepMax: 12))
    }

    @Test
    func alreadyAppliedOverloadQualifiesDespiteResetReps() {
        // After applying, actual reps are reset to the range minimum — the flag
        // must keep the exercise qualified (the goal was hit to get here).
        #expect(ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: completedSets(reps: [8, 8, 8]),
            targetRepMax: 12,
            overloadAlreadyApplied: true
        ))
    }

    // MARK: - Qualify (routine template)

    @Test
    func templateQualifiesWhenAllSetsAtOrAboveMax() {
        #expect(ProgressiveOverloadService.templateQualifiesForIncrease(reps: [12, 13], targetRepMax: 12))
        #expect(!ProgressiveOverloadService.templateQualifiesForIncrease(reps: [12, 11], targetRepMax: 12))
        #expect(!ProgressiveOverloadService.templateQualifiesForIncrease(reps: [], targetRepMax: 12))
        #expect(!ProgressiveOverloadService.templateQualifiesForIncrease(reps: [12, 12], targetRepMax: nil))
    }

    // MARK: - Apply

    @Test
    func resistanceIncreaseAppliesIncrementToAllSetsAndResetsReps() {
        let increase = ProgressiveOverloadService.applyIncrease(
            toWeights: [60, 62.5, 65],
            increment: 2.5,
            targetRepMin: 8,
            loadBehavior: .resistance
        )
        #expect(increase.weights == [62.5, 65, 67.5])
        #expect(increase.reps == 8)
    }

    @Test
    func counterweightAssistanceIncreaseReducesWeight() {
        let increase = ProgressiveOverloadService.applyIncrease(
            toWeights: [30, 30],
            increment: 2.5,
            targetRepMin: 8,
            loadBehavior: .counterweightAssistance
        )
        #expect(increase.weights == [27.5, 27.5])
        #expect(increase.reps == 8)
    }

    @Test
    func counterweightAssistanceClampsAtZero() {
        #expect(ProgressiveOverloadService.increasedWeight(1.0, increment: 2.5, loadBehavior: .counterweightAssistance) == 0)
    }

    /// The watch-only half of the copy: the wire models carry load behavior as a
    /// raw string, so `from(raw:)` is the single place a bad/absent value could
    /// silently reverse the direction of a weight change.
    @Test
    func unknownOrAbsentLoadBehaviorRawDegradesToResistance() {
        #expect(ExerciseLoadBehavior.from(raw: "resistance") == .resistance)
        #expect(ExerciseLoadBehavior.from(raw: "counterweightAssistance") == .counterweightAssistance)
        #expect(ExerciseLoadBehavior.from(raw: nil) == .resistance)
        #expect(ExerciseLoadBehavior.from(raw: "") == .resistance)
        #expect(ExerciseLoadBehavior.from(raw: "somethingIOSAddedLater") == .resistance)
    }

    // MARK: - Increment grids (per display unit)
    //
    // Kept identical to the iOS twin: the two `ProgressiveOverloadIncrement`
    // copies are per-target duplicates, and a drift means the watch proposes a
    // different increase than the phone for the same set.

    @Test
    func normalizedClampsToEachUnitsSelectableRange() {
        for unit in WeightUnit.allCases {
            let grid = ProgressiveOverloadIncrement.grid(for: unit)
            #expect(ProgressiveOverloadIncrement.normalized(0, in: unit) == grid.minimum)
            #expect(ProgressiveOverloadIncrement.normalized(-5, in: unit) == grid.minimum)
            #expect(ProgressiveOverloadIncrement.normalized(999, in: unit) == grid.maximum)
        }
    }

    @Test
    func normalizedSnapsToTheNearestStride() {
        #expect(ProgressiveOverloadIncrement.normalized(2.6, in: .kilograms) == 2.5)
        #expect(ProgressiveOverloadIncrement.normalized(2.63, in: .kilograms) == 2.75)
        // Float drift from repeated crown writes must not survive.
        #expect(ProgressiveOverloadIncrement.normalized(1.2500000001, in: .kilograms) == 1.25)

        // Pounds share the 0.25 stride, which is what keeps 1.25 lb reachable.
        #expect(ProgressiveOverloadIncrement.normalized(5.1, in: .pounds) == 5)
        #expect(ProgressiveOverloadIncrement.normalized(1.3, in: .pounds) == 1.25)
        #expect(ProgressiveOverloadIncrement.normalized(1.2500000001, in: .pounds) == 1.25)
    }

    @Test
    func everyPresetLandsExactlyOnItsUnitsStrideGrid() {
        // The presets are reachable by crown only if they sit on the grid —
        // otherwise the picker could never highlight them.
        for unit in WeightUnit.allCases {
            let grid = ProgressiveOverloadIncrement.grid(for: unit)
            for preset in grid.options {
                #expect(ProgressiveOverloadIncrement.normalized(preset, in: unit) == preset,
                        "preset \(preset) is off the \(grid.step) grid of \(unit)")
                #expect(preset >= grid.minimum)
                #expect(preset <= grid.maximum)
            }
            #expect(grid.options.contains(grid.defaultOption))
        }
    }

    @Test
    func poundIncrementsAreRealPlateStepsRatherThanConvertedKilograms() {
        let kilograms = ProgressiveOverloadIncrement.grid(for: .kilograms)
        let pounds = ProgressiveOverloadIncrement.grid(for: .pounds)

        #expect(pounds.options == [1.25, 2.5, 5, 10])
        #expect(pounds.defaultOption == 5)

        // Converting the kilogram list would give 1.1 / 2.76 / 5.51 / 11.02 lb.
        // Nobody racks a 2.76 lb plate, so the two grids must not match.
        let converted = kilograms.options.map { WeightUnit.pounds.converting(fromKilograms: $0) }
        for option in pounds.options {
            #expect(!converted.contains(option),
                    "\(option) lb looks like a converted kilogram step, not a plate step")
        }
    }
}
