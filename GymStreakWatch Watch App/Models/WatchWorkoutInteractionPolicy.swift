import Foundation

enum WatchWorkoutFinishDialogState: Equatable {
    case unchanged
    case setsOnly(count: Int)
    case structuralOnly
    /// Only the rest duration was adjusted (ticket 04, rest in the template
    /// transaction). Rest is one change per exercise rather than per set, so it
    /// carries no count, and it is the weakest of the three signals: any set or
    /// structural change already offers the template update and rest rides
    /// along with it.
    case restOnly
    case combined(modifiedSetCount: Int)
}

struct WatchWorkoutSetLocation: Equatable {
    let exerciseIndex: Int
    let setIndex: Int
}

enum WatchWorkoutInteractionPolicy {
    static func finishDialogState(
        modifiedSetCount: Int,
        hasStructuralChanges: Bool,
        hasRestChanges: Bool = false
    ) -> WatchWorkoutFinishDialogState {
        if modifiedSetCount > 0 && hasStructuralChanges {
            return .combined(modifiedSetCount: modifiedSetCount)
        }
        if hasStructuralChanges { return .structuralOnly }
        if modifiedSetCount > 0 { return .setsOnly(count: modifiedSetCount) }
        if hasRestChanges { return .restOnly }
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
