import Foundation
import Testing
@testable import GymStreak

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
