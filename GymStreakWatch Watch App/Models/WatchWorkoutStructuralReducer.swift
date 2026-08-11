import Foundation

// This pure reducer is duplicated in the iOS target. Keeping it Foundation-
// only lets the existing iOS unit-test target cover the watch state machine.

enum WatchExerciseCatalogDisplayState: Equatable {
    case neverSynced
    case empty
    case populated([WatchExerciseCatalogItem])
}

struct WatchExerciseSelection: Equatable {
    let exerciseID: UUID
    let seedKey: String?

    init(exerciseID: UUID, seedKey: String?) {
        self.exerciseID = exerciseID
        self.seedKey = Self.nonEmpty(seedKey)
    }

    init(item: WatchExerciseCatalogItem) {
        self.init(exerciseID: item.id, seedKey: item.seedKey)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct WatchExerciseConfigurationDraft: Equatable {
    var setCount: Int
    var reps: Int
    var weight: Double
    var restSeconds: Int

    init(setCount: Int = 1, reps: Int = 10, weight: Double = 0, restSeconds: Int = 60) {
        self.setCount = min(max(setCount, 1), 20)
        self.reps = min(max(reps, 1), 100)
        self.weight = min(max(weight.rounded(), 0), 999)
        self.restSeconds = min(max((restSeconds / 30) * 30, 0), 300)
    }
}

struct WatchWorkoutStructuralChanges: Equatable {
    let sessionAddedSlotIDs: Set<UUID>
    let sessionRemovedSlotIDs: Set<UUID>
    let outgoingAddedSlotIDs: [UUID]
    let outgoingRemovedSlotIDs: [UUID]

    var hasStructuralChanges: Bool {
        !sessionAddedSlotIDs.isEmpty || !sessionRemovedSlotIDs.isEmpty
    }
}

struct WatchWorkoutStructuralBaseline: Equatable, Codable {
    let knownSlotIDsInOrder: [UUID]
    let authoritativeSlotIDsInOrder: [UUID]
    let knownSlotIDSet: Set<UUID>
    let authoritativeSlotIDSet: Set<UUID>

    init(exercises: [WatchExercise]) {
        let ordered = exercises.sorted { $0.order < $1.order }
        knownSlotIDsInOrder = ordered.map(\.id)
        authoritativeSlotIDsInOrder = ordered
            .filter { $0.isPendingWatchAddition != true }
            .map(\.id)
        knownSlotIDSet = Set(knownSlotIDsInOrder)
        authoritativeSlotIDSet = Set(authoritativeSlotIDsInOrder)
    }

    func changes(for exercises: [ActiveWorkoutExercise]) -> WatchWorkoutStructuralChanges {
        let finalIDs = exercises.sorted { $0.order < $1.order }.map(\.id)
        let finalIDSet = Set(finalIDs)
        return WatchWorkoutStructuralChanges(
            sessionAddedSlotIDs: finalIDSet.subtracting(knownSlotIDSet),
            sessionRemovedSlotIDs: knownSlotIDSet.subtracting(finalIDSet),
            outgoingAddedSlotIDs: finalIDs.filter { !authoritativeSlotIDSet.contains($0) },
            outgoingRemovedSlotIDs: knownSlotIDsInOrder.filter { !finalIDSet.contains($0) }
        )
    }
}

struct WatchWorkoutProgressSegment: Identifiable, Equatable {
    let id: UUID
    let fraction: Double
}

struct WatchWorkoutRemovalResult: Equatable {
    let removedSlotID: UUID
    let removedCompletedSetCount: Int
}

enum WatchWorkoutStructuralReducer {
    static func catalogueState(
        hasReceivedCatalog: Bool,
        items: [WatchExerciseCatalogItem]
    ) -> WatchExerciseCatalogDisplayState {
        guard hasReceivedCatalog else { return .neverSynced }
        return items.isEmpty ? .empty : .populated(items)
    }

    static func resolve(
        _ selection: WatchExerciseSelection,
        in items: [WatchExerciseCatalogItem]
    ) -> WatchExerciseCatalogItem? {
        if let exact = items.first(where: { $0.id == selection.exerciseID }) {
            return exact
        }
        guard let seedKey = selection.seedKey else { return nil }
        return items.first { nonEmpty($0.seedKey) == seedKey }
    }

    static func isAlreadyActive(
        _ item: WatchExerciseCatalogItem,
        in exercises: [ActiveWorkoutExercise]
    ) -> Bool {
        let itemSeedKey = nonEmpty(item.seedKey)
        return exercises.contains { exercise in
            if exercise.exerciseId == item.id {
                return true
            }
            if let activeSeedKey = nonEmpty(exercise.exerciseSeedKey),
               let itemSeedKey {
                return activeSeedKey == itemSeedKey
            }
            guard exercise.exerciseId == nil,
                  nonEmpty(exercise.exerciseSeedKey) == nil else { return false }
            return normalizedName(exercise.name) == normalizedName(item.name)
        }
    }

    static func makeExercise(
        item: WatchExerciseCatalogItem,
        draft: WatchExerciseConfigurationDraft,
        order: Int,
        slotID: UUID,
        setIDs: [UUID]
    ) -> ActiveWorkoutExercise? {
        guard setIDs.count == draft.setCount,
              Set(setIDs).count == setIDs.count else { return nil }
        let sets = setIDs.enumerated().map { index, id in
            ActiveWorkoutSet(
                id: id,
                plannedReps: draft.reps,
                actualReps: draft.reps,
                plannedWeight: draft.weight,
                actualWeight: draft.weight,
                restTime: TimeInterval(draft.restSeconds),
                plannedRestTime: TimeInterval(draft.restSeconds),
                completedAt: nil,
                order: index
            )
        }
        return ActiveWorkoutExercise(
            id: slotID,
            name: item.name,
            muscleGroup: item.muscleGroups.first ?? "General",
            sets: sets,
            order: order,
            supersetId: nil,
            supersetOrder: 0,
            targetRepMin: nil,
            targetRepMax: nil,
            exerciseId: item.id,
            exerciseSeedKey: nonEmpty(item.seedKey),
            isPendingWatchAddition: true,
            loadBehaviorRaw: item.loadBehaviorRaw,
            alternatives: []
        )
    }

    @discardableResult
    static func remove(
        slotID: UUID,
        from exercises: inout [ActiveWorkoutExercise],
        currentExerciseIndex: inout Int,
        currentSetIndex: inout Int
    ) -> WatchWorkoutRemovalResult? {
        guard let removedIndex = exercises.firstIndex(where: { $0.id == slotID }) else {
            return nil
        }
        let removed = exercises[removedIndex]
        let currentSupersetID = removed.supersetId
        exercises.remove(at: removedIndex)

        for index in exercises.indices {
            exercises[index].order = index
        }

        if let currentSupersetID {
            let remaining = exercises.indices.filter {
                exercises[$0].supersetId == currentSupersetID
            }
            if remaining.count >= 2 {
                let ordered = remaining.sorted {
                    exercises[$0].supersetOrder < exercises[$1].supersetOrder
                }
                for (supersetOrder, index) in ordered.enumerated() {
                    exercises[index].supersetOrder = supersetOrder
                }
            } else if let survivor = remaining.first {
                exercises[survivor].supersetId = nil
                exercises[survivor].supersetOrder = 0
            }
        }

        if exercises.isEmpty {
            currentExerciseIndex = 0
            currentSetIndex = 0
        } else {
            if removedIndex < currentExerciseIndex {
                currentExerciseIndex -= 1
            } else if removedIndex == currentExerciseIndex {
                currentExerciseIndex = min(removedIndex, exercises.count - 1)
            }
            currentExerciseIndex = min(max(currentExerciseIndex, 0), exercises.count - 1)
            currentSetIndex = exercises[currentExerciseIndex].sets
                .firstIndex(where: { !$0.isCompleted }) ?? 0
        }

        return WatchWorkoutRemovalResult(
            removedSlotID: removed.id,
            removedCompletedSetCount: removed.completedSetsCount
        )
    }

    static func progressSegments(
        for exercises: [ActiveWorkoutExercise]
    ) -> [WatchWorkoutProgressSegment] {
        exercises.sorted { $0.order < $1.order }.map { exercise in
            let fraction = exercise.sets.isEmpty
                ? 0
                : Double(exercise.completedSetsCount) / Double(exercise.sets.count)
            return WatchWorkoutProgressSegment(id: exercise.id, fraction: fraction)
        }
    }

    static func hasUniqueIdentities(_ exercises: [ActiveWorkoutExercise]) -> Bool {
        let slotIDs = exercises.map(\.id)
        let setIDs = exercises.flatMap(\.sets).map(\.id)
        return Set(slotIDs).count == slotIDs.count && Set(setIDs).count == setIDs.count
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
