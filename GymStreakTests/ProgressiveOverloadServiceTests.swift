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
}
