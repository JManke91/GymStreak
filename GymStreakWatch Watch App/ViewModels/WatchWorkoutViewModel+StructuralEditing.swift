import Foundation
import WatchKit

extension WatchWorkoutViewModel {
    private var structuralChanges: WatchWorkoutStructuralChanges {
        structuralBaseline?.changes(for: exercises) ?? WatchWorkoutStructuralChanges(
            sessionAddedSlotIDs: [],
            sessionRemovedSlotIDs: [],
            outgoingAddedSlotIDs: [],
            outgoingRemovedSlotIDs: []
        )
    }

    var sessionAddedSlotIDSet: Set<UUID> { structuralChanges.sessionAddedSlotIDs }
    var sessionRemovedSlotIDSet: Set<UUID> { structuralChanges.sessionRemovedSlotIDs }
    var outgoingAddedSlotIDs: [UUID] { structuralChanges.outgoingAddedSlotIDs }
    var outgoingRemovedSlotIDs: [UUID] { structuralChanges.outgoingRemovedSlotIDs }
    var hasStructuralChanges: Bool { structuralChanges.hasStructuralChanges }
    var hasTemplateChanges: Bool { hasModifiedSets || hasStructuralChanges }
    var finishDialogState: WatchWorkoutFinishDialogState {
        WatchWorkoutInteractionPolicy.finishDialogState(
            modifiedSetCount: modifiedSetsCount,
            hasStructuralChanges: hasStructuralChanges
        )
    }

    var progressSegments: [WatchWorkoutProgressSegment] {
        WatchWorkoutStructuralReducer.progressSegments(for: exercises)
    }

    func beginExerciseCatalogue() {
        guard !isWorkoutFrozen else { return }
        cancelDelayedAutoFinish()
        pendingExerciseSelection = nil
        isWorkoutInputSuspended = true
    }

    func beginExerciseConfiguration(item: WatchExerciseCatalogItem) {
        guard !isWorkoutFrozen else { return }
        cancelDelayedAutoFinish()
        pendingExerciseSelection = WatchExerciseSelection(item: item)
        isWorkoutInputSuspended = true
    }

    /// Called as the typed navigation path changes. Going back from the
    /// configuration screen discards its selection; leaving the whole flow
    /// re-enables workout input.
    func updateExerciseEditingState(isInCatalogueFlow: Bool, isConfiguring: Bool) {
        if !isConfiguring {
            pendingExerciseSelection = nil
        }
        isWorkoutInputSuspended = isInCatalogueFlow || isConfiguring
    }

    func prepareForTerminalPresentation() {
        cancelDelayedAutoFinish()
        pendingExerciseSelection = nil
        isWorkoutInputSuspended = false
    }

    func cancelDelayedAutoFinish() {
        autoFinishTask?.cancel()
        autoFinishTask = nil
    }

    func goToExercise(slotID: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == slotID }) else { return }
        goToExercise(at: index)
    }

    func exercise(slotID: UUID) -> ActiveWorkoutExercise? {
        exercises.first { $0.id == slotID }
    }

    @discardableResult
    func addConfiguredExercise(
        draft: WatchExerciseConfigurationDraft,
        catalogueItems: [WatchExerciseCatalogItem]
    ) -> UUID? {
        guard !isWorkoutFrozen, let pendingExerciseSelection else { return nil }
        cancelDelayedAutoFinish()

        guard let item = WatchWorkoutStructuralReducer.resolve(
            pendingExerciseSelection,
            in: catalogueItems
        ) else {
            errorMessage = String(localized: "This exercise is no longer available in your iPhone library.")
            return nil
        }
        guard !WatchWorkoutStructuralReducer.isAlreadyActive(item, in: exercises) else {
            errorMessage = String(localized: "This exercise is already in the workout.")
            return nil
        }

        let existingSlotIDs = Set(exercises.map(\.id))
        var slotID = UUID()
        while existingSlotIDs.contains(slotID) { slotID = UUID() }

        var usedSetIDs = Set(exercises.flatMap(\.sets).map(\.id))
        var setIDs: [UUID] = []
        while setIDs.count < draft.setCount {
            let candidate = UUID()
            if usedSetIDs.insert(candidate).inserted {
                setIDs.append(candidate)
            }
        }

        guard let exercise = WatchWorkoutStructuralReducer.makeExercise(
            item: item,
            draft: draft,
            order: exercises.count,
            slotID: slotID,
            setIDs: setIDs
        ) else {
            assertionFailure("Validated exercise draft could not be materialized")
            return nil
        }

        exercises.append(exercise)
        currentExerciseIndex = exercises.count - 1
        currentSetIndex = 0
        self.pendingExerciseSelection = nil
        isWorkoutInputSuspended = false
        assert(WatchWorkoutStructuralReducer.hasUniqueIdentities(exercises))
        WKInterfaceDevice.current().play(.success)
        return slotID
    }

    @discardableResult
    func removeExercise(slotID: UUID) -> WatchWorkoutRemovalResult? {
        guard canMutateWorkout else { return nil }
        cancelDelayedAutoFinish()
        let result = WatchWorkoutStructuralReducer.remove(
            slotID: slotID,
            from: &exercises,
            currentExerciseIndex: &currentExerciseIndex,
            currentSetIndex: &currentSetIndex
        )
        if result != nil {
            assert(WatchWorkoutStructuralReducer.hasUniqueIdentities(exercises))
            WKInterfaceDevice.current().play(.success)
        }
        return result
    }
}
