//
//  WatchWorkoutInteractionPolicyTests.swift
//  GymStreakWatchTests
//
//  Watch-side twin of `GymStreakTests/WatchWorkoutInteractionPolicyTests.swift`.
//  Same reasoning as the structural-reducer twin: the policy is duplicated per
//  target and only the iOS copy was ever asserted on before this target existed.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@MainActor
extension WatchWorkoutStructuralReducerTests {
    @Test
    func finishDialogStateDistinguishesSetStructuralAndCombinedChanges() {
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0,
            hasStructuralChanges: false
        ) == .unchanged)
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 2,
            hasStructuralChanges: false
        ) == .setsOnly(count: 2))
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0,
            hasStructuralChanges: true
        ) == .structuralOnly)
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 2,
            hasStructuralChanges: true
        ) == .combined(modifiedSetCount: 2))
    }

    /// Rest is the weakest finish-dialog signal: it only surfaces when nothing
    /// else changed, and any set or structural change subsumes it.
    @Test
    func restOnlyChangesOfferTheTemplateUpdateButAreSubsumedByStrongerSignals() {
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0,
            hasStructuralChanges: false,
            hasRestChanges: true
        ) == .restOnly)
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 1,
            hasStructuralChanges: false,
            hasRestChanges: true
        ) == .setsOnly(count: 1))
        #expect(WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: 0,
            hasStructuralChanges: true,
            hasRestChanges: true
        ) == .structuralOnly)
    }

    @Test
    func autoFinishAndMutationPoliciesRejectSuspendedEndingOrCancelledInput() {
        #expect(WatchWorkoutInteractionPolicy.allowsMutation(
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            isInputSuspended: false
        ))
        #expect(!WatchWorkoutInteractionPolicy.allowsMutation(
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            isInputSuspended: true
        ))
        #expect(!WatchWorkoutInteractionPolicy.allowsMutation(
            isWorkoutActive: true,
            isWorkoutFrozen: true,
            isInputSuspended: false
        ))
        #expect(WatchWorkoutInteractionPolicy.allowsConfiguredAdd(
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            hasPendingSelection: true
        ))
        #expect(!WatchWorkoutInteractionPolicy.allowsConfiguredAdd(
            isWorkoutActive: false,
            isWorkoutFrozen: false,
            hasPendingSelection: true
        ))
        #expect(!WatchWorkoutInteractionPolicy.allowsConfiguredAdd(
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            hasPendingSelection: false
        ))
        #expect(WatchWorkoutInteractionPolicy.shouldAutoFinish(
            isTaskCancelled: false,
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            isInputSuspended: false,
            hasIncompleteSet: false
        ))
        #expect(!WatchWorkoutInteractionPolicy.shouldAutoFinish(
            isTaskCancelled: true,
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            isInputSuspended: false,
            hasIncompleteSet: false
        ))
        #expect(!WatchWorkoutInteractionPolicy.shouldAutoFinish(
            isTaskCancelled: false,
            isWorkoutActive: true,
            isWorkoutFrozen: false,
            isInputSuspended: true,
            hasIncompleteSet: false
        ))
    }

    @Test
    func asyncSetResultReResolvesUUIDsAfterIndexShiftAndRejectsRemovedTarget() throws {
        let first = makeActiveExercise(order: 0)
        let target = makeActiveExercise(order: 1)
        let targetSetID = try #require(target.sets.first?.id)
        var exercises = [first, target]
        var exerciseIndex = 0
        var setIndex = 0

        WatchWorkoutStructuralReducer.remove(
            slotID: first.id,
            from: &exercises,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(WatchWorkoutInteractionPolicy.setLocation(
            exerciseID: target.id,
            setID: targetSetID,
            in: exercises
        ) == .init(exerciseIndex: 0, setIndex: 0))

        WatchWorkoutStructuralReducer.remove(
            slotID: target.id,
            from: &exercises,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(WatchWorkoutInteractionPolicy.setLocation(
            exerciseID: target.id,
            setID: targetSetID,
            in: exercises
        ) == nil)
    }
}
