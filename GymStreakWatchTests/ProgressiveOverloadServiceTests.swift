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

    // MARK: - Increment scale (watch Digital Crown picker)

    @Test
    func normalizedClampsToTheSelectableRange() {
        #expect(ProgressiveOverloadIncrement.normalized(0) == ProgressiveOverloadIncrement.minimum)
        #expect(ProgressiveOverloadIncrement.normalized(-5) == ProgressiveOverloadIncrement.minimum)
        #expect(ProgressiveOverloadIncrement.normalized(999) == ProgressiveOverloadIncrement.maximum)
    }

    @Test
    func normalizedSnapsToTheNearestStride() {
        #expect(ProgressiveOverloadIncrement.normalized(2.6) == 2.5)
        #expect(ProgressiveOverloadIncrement.normalized(2.63) == 2.75)
        // Float drift from repeated crown writes must not survive.
        #expect(ProgressiveOverloadIncrement.normalized(1.2500000001) == 1.25)
    }

    @Test
    func everyPresetLandsExactlyOnTheStrideGrid() {
        // The presets are reachable by crown only if they sit on the grid —
        // otherwise the picker could never highlight them.
        for preset in ProgressiveOverloadIncrement.options {
            #expect(ProgressiveOverloadIncrement.normalized(preset) == preset,
                    "preset \(preset) is off the \(ProgressiveOverloadIncrement.step) grid")
            #expect(preset >= ProgressiveOverloadIncrement.minimum)
            #expect(preset <= ProgressiveOverloadIncrement.maximum)
        }
        #expect(ProgressiveOverloadIncrement.options.contains(ProgressiveOverloadIncrement.default))
    }
}
