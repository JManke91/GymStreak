//
//  ProgressiveOverloadServiceTests.swift
//  GymStreakTests
//
//  Covers the shared progressive-overload domain logic: when an exercise
//  qualifies for a weight-increase suggestion and the apply-increase math.
//

import Testing
@testable import GymStreak

@Suite
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

    // MARK: - Increment grids (per display unit)

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

    @Test
    func poundMicroPlateStillRendersBothItsDecimals() {
        // `%.2g` renders 1.25 as "1.2"; the seam's fraction-length precision is
        // what stops a valid 1.25 lb step from reading as an invalid one.
        // Not the literal "1.25": these styles use `Locale.autoupdatingCurrent`,
        // and a German machine renders "1,25".
        let bothDecimals = 1.25.formatted(.number.precision(.fractionLength(0...2)))
        #expect(WeightFormatting.incrementLabel(1.25, in: .kilograms).hasPrefix(bothDecimals))
        #expect(WeightFormatting.incrementLabel(1.25, in: .pounds).hasPrefix(bothDecimals))
        // The reason it needs its own style: the pound *weight* style keeps one
        // decimal, which would round the step to "1.3".
        #expect(WeightFormatting.displayNumber(1.25, in: .pounds) != bothDecimals)
    }

    // MARK: - Uniformity

    /// The verdict that decides whether a confirmed increase may name a weight
    /// at all. Every surface reaches it through this one rule.
    @Test
    func aSingleSharedWeightIsUniformAndAPyramidIsNot() {
        #expect(ProgressiveOverloadService.haveUniformWeights([62.5, 62.5, 62.5]))
        #expect(ProgressiveOverloadService.haveUniformWeights([62.5]))
        #expect(!ProgressiveOverloadService.haveUniformWeights([62.5, 65, 67.5]))
        // Drop set: the fall is at the end, not the start.
        #expect(!ProgressiveOverloadService.haveUniformWeights([62.5, 62.5, 50]))
        // Vacuously uniform — callers needing a nameable number check `first`.
        #expect(ProgressiveOverloadService.haveUniformWeights([]))
    }

    /// A JSON round trip and a recomputed template weight can differ in the last
    /// bit, which is not a pyramid.
    @Test
    func aLastBitDifferenceIsStillOneWeight() {
        #expect(ProgressiveOverloadService.weightsMatch(62.5, 62.500_02))
        #expect(!ProgressiveOverloadService.weightsMatch(62.5, 62.6))
        #expect(ProgressiveOverloadService.haveUniformWeights([62.5, 62.500_02]))
    }

    /// `weightsMatch` is a tolerance comparison and therefore NOT transitive.
    /// Anchoring every comparison on the FIRST weight is what makes independent
    /// surfaces agree on the same scheme; a pairwise chain would not, and this
    /// input is the one that shows the difference.
    @Test
    func theVerdictIsAnchoredOnTheFirstWeightRatherThanChained() {
        #expect(!ProgressiveOverloadService.haveUniformWeights(
            [62.5, 62.500_05, 62.500_1, 62.500_15, 62.500_2]
        ))
    }
}
