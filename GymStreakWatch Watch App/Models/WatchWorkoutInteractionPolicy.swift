import Foundation

enum WatchWorkoutFinishDialogState: Equatable {
    case unchanged
    case setsOnly(count: Int)
    case structuralOnly
    case combined(modifiedSetCount: Int)
}

struct WatchWorkoutSetLocation: Equatable {
    let exerciseIndex: Int
    let setIndex: Int
}

enum WatchWorkoutInteractionPolicy {
    static func finishDialogState(
        modifiedSetCount: Int,
        hasStructuralChanges: Bool
    ) -> WatchWorkoutFinishDialogState {
        if modifiedSetCount > 0 && hasStructuralChanges {
            return .combined(modifiedSetCount: modifiedSetCount)
        }
        if hasStructuralChanges { return .structuralOnly }
        if modifiedSetCount > 0 { return .setsOnly(count: modifiedSetCount) }
        return .unchanged
    }

    static func allowsMutation(
        isWorkoutActive: Bool,
        isWorkoutFrozen: Bool,
        isInputSuspended: Bool
    ) -> Bool {
        isWorkoutActive && !isWorkoutFrozen && !isInputSuspended
    }

    static func allowsConfiguredAdd(
        isWorkoutActive: Bool,
        isWorkoutFrozen: Bool,
        hasPendingSelection: Bool
    ) -> Bool {
        isWorkoutActive && !isWorkoutFrozen && hasPendingSelection
    }

    static func shouldAutoFinish(
        isTaskCancelled: Bool,
        isWorkoutActive: Bool,
        isWorkoutFrozen: Bool,
        isInputSuspended: Bool,
        hasIncompleteSet: Bool
    ) -> Bool {
        !isTaskCancelled
            && allowsMutation(
                isWorkoutActive: isWorkoutActive,
                isWorkoutFrozen: isWorkoutFrozen,
                isInputSuspended: isInputSuspended
            )
            && !hasIncompleteSet
    }

    static func setLocation(
        exerciseID: UUID,
        setID: UUID,
        in exercises: [ActiveWorkoutExercise]
    ) -> WatchWorkoutSetLocation? {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else {
            return nil
        }
        return WatchWorkoutSetLocation(exerciseIndex: exerciseIndex, setIndex: setIndex)
    }
}
