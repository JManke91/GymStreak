//
//  WatchWorkoutStructuralReducerTests.swift
//  GymStreakWatchTests
//
//  Watch-side twin of `GymStreakTests/WatchWorkoutStructuralReducerTests.swift`.
//  The reducer is duplicated per target (see the header of
//  `Models/WatchWorkoutStructuralReducer.swift`); until this target existed the
//  watch copy had no coverage at all and only the iOS copy was ever asserted on.
//  Assertions are kept deliberately identical to the iOS twin so a behavioural
//  drift between the two copies fails here.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@MainActor
struct WatchWorkoutStructuralReducerTests {
    @Test
    func catalogueStateDistinguishesNeverSyncedEmptyAndPopulatedLibraries() {
        let item = makeCatalogItem(name: "Bench Press")

        #expect(WatchWorkoutStructuralReducer.catalogueState(hasReceivedCatalog: false, items: []) == .neverSynced)
        #expect(WatchWorkoutStructuralReducer.catalogueState(hasReceivedCatalog: true, items: []) == .empty)
        #expect(WatchWorkoutStructuralReducer.catalogueState(hasReceivedCatalog: true, items: [item]) == .populated([item]))
    }

    @Test
    func catalogueMatchingUsesUUIDThenSeedKeyAndOnlyFallsBackToNameForLegacySlots() {
        let libraryID = UUID()
        let item = makeCatalogItem(id: libraryID, seedKey: "seed.bench", name: "Bench Press")

        #expect(WatchWorkoutStructuralReducer.isAlreadyActive(
            item,
            in: [makeActiveExercise(exerciseID: libraryID, name: "Renamed")]
        ))
        #expect(WatchWorkoutStructuralReducer.isAlreadyActive(
            item,
            in: [makeActiveExercise(exerciseID: UUID(), seedKey: "seed.bench", name: "Renamed")]
        ))
        #expect(WatchWorkoutStructuralReducer.isAlreadyActive(
            item,
            in: [makeActiveExercise(exerciseID: nil, seedKey: nil, name: " bench press ")]
        ))
        #expect(!WatchWorkoutStructuralReducer.isAlreadyActive(
            item,
            in: [makeActiveExercise(exerciseID: UUID(), seedKey: nil, name: "Bench Press")]
        ))
    }

    @Test
    func staleSelectionResolvesBySeedKeyOrLeavesWorkoutUnchanged() {
        let selection = WatchExerciseSelection(exerciseID: UUID(), seedKey: "seed.row")
        let replacement = makeCatalogItem(seedKey: "seed.row", name: "Cable Row")

        #expect(WatchWorkoutStructuralReducer.resolve(selection, in: [replacement]) == replacement)
        #expect(WatchWorkoutStructuralReducer.resolve(selection, in: []) == nil)
    }

    @Test
    func draftBoundsAndAtomicExerciseCreationPreserveConfiguredMetadataAndUniqueIDs() throws {
        #expect(WatchExerciseConfigurationDraft() == .init(setCount: 1, reps: 10, weight: 0, restSeconds: 60))
        #expect(WatchExerciseConfigurationDraft(setCount: 99, reps: 0, weight: 1_500, restSeconds: 319)
            == .init(setCount: 20, reps: 1, weight: 999, restSeconds: 300))

        let slotID = UUID()
        let setIDs = [UUID(), UUID(), UUID()]
        let item = WatchExerciseCatalogItem(
            id: UUID(),
            seedKey: "seed.squat",
            name: "Back Squat",
            muscleGroups: ["Legs", "Core"],
            equipmentTypeRaw: "barbell",
            loadBehaviorRaw: "resistance"
        )
        let exercise = try #require(WatchWorkoutStructuralReducer.makeExercise(
            item: item,
            draft: .init(setCount: 3, reps: 8, weight: 100, restSeconds: 90),
            order: 2,
            slotID: slotID,
            setIDs: setIDs
        ))

        #expect(exercise.id == slotID)
        #expect(exercise.exerciseId == item.id)
        #expect(exercise.exerciseSeedKey == "seed.squat")
        #expect(exercise.muscleGroup == "Legs")
        #expect(exercise.loadBehaviorRaw == "resistance")
        #expect(exercise.isPendingWatchAddition)
        #expect(exercise.supersetId == nil && exercise.supersetOrder == 0)
        #expect(exercise.targetRepMin == nil && exercise.targetRepMax == nil)
        #expect(exercise.sets.map(\.id) == setIDs)
        #expect(exercise.sets.map(\.order) == [0, 1, 2])
        #expect(exercise.sets.allSatisfy {
            $0.plannedReps == 8 && $0.actualReps == 8
                && $0.plannedWeight == 100 && $0.actualWeight == 100
                && $0.restTime == 90 && $0.completedAt == nil
        })
        #expect(WatchWorkoutStructuralReducer.hasUniqueIdentities([exercise]))
        #expect(WatchWorkoutStructuralReducer.makeExercise(
            item: item,
            draft: .init(setCount: 2),
            order: 0,
            slotID: UUID(),
            setIDs: [UUID()]
        ) == nil)
    }

    @Test
    func baselineDerivesSessionAndOrderedOutgoingNetChanges() {
        let authoritative = makeWatchExercise(id: UUID(), order: 0)
        let pending = makeWatchExercise(id: UUID(), order: 1, isPending: true)
        let baseline = WatchWorkoutStructuralBaseline(exercises: [authoritative, pending])
        let newSlot = makeActiveExercise(id: UUID(), order: 1)

        let changed = baseline.changes(for: [authoritative.toTestActive(), newSlot])
        #expect(changed.sessionAddedSlotIDs == [newSlot.id])
        #expect(changed.sessionRemovedSlotIDs == [pending.id])
        #expect(changed.outgoingAddedSlotIDs == [newSlot.id])
        #expect(changed.outgoingRemovedSlotIDs == [pending.id])

        let unchanged = baseline.changes(for: [authoritative.toTestActive(), pending.toTestActive()])
        #expect(unchanged.sessionAddedSlotIDs.isEmpty)
        #expect(unchanged.sessionRemovedSlotIDs.isEmpty)
        #expect(unchanged.outgoingAddedSlotIDs == [pending.id])
        #expect(unchanged.outgoingRemovedSlotIDs.isEmpty)
    }

    @Test
    func addThenRemoveCancelsButRemoveThenReaddSameLibraryExerciseUsesNewSlotIdentity() {
        let original = makeWatchExercise(id: UUID(), order: 0)
        let baseline = WatchWorkoutStructuralBaseline(exercises: [original])
        let temporary = makeActiveExercise(id: UUID(), order: 1)

        #expect(!baseline.changes(for: [original.toTestActive()]).hasStructuralChanges)

        let replacement = makeActiveExercise(id: UUID(), exerciseID: original.exerciseId, order: 0)
        let replacementChanges = baseline.changes(for: [replacement])
        #expect(replacementChanges.sessionAddedSlotIDs == [replacement.id])
        #expect(replacementChanges.sessionRemovedSlotIDs == [original.id])
        #expect(replacementChanges.outgoingAddedSlotIDs == [replacement.id])
        #expect(replacementChanges.outgoingRemovedSlotIDs == [original.id])

        let addThenRemove = baseline.changes(for: [original.toTestActive(), temporary].filter { $0.id != temporary.id })
        #expect(!addThenRemove.hasStructuralChanges)
    }

    @Test
    func removalReconcilesCursorAndAllowsZeroExercises() {
        let first = makeActiveExercise(id: UUID(), order: 0)
        let second = makeActiveExercise(id: UUID(), order: 1, setCompleted: true)
        let third = makeActiveExercise(id: UUID(), order: 2)
        var exercises = [first, second, third]
        var exerciseIndex = 1
        var setIndex = 0

        WatchWorkoutStructuralReducer.remove(
            slotID: first.id,
            from: &exercises,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(exerciseIndex == 0)
        #expect(exercises.map(\.order) == [0, 1])

        WatchWorkoutStructuralReducer.remove(
            slotID: second.id,
            from: &exercises,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(exerciseIndex == 0)
        #expect(exercises[0].id == third.id)
        #expect(setIndex == 0)

        WatchWorkoutStructuralReducer.remove(
            slotID: third.id,
            from: &exercises,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(exercises.isEmpty)
        #expect(exerciseIndex == 0 && setIndex == 0)
    }

    @Test
    func removalDissolvesTwoMemberSupersetAndRenumbersThreeMemberSuperset() {
        let groupID = UUID()
        let first = makeActiveExercise(id: UUID(), order: 0, supersetID: groupID, supersetOrder: 0)
        let second = makeActiveExercise(id: UUID(), order: 1, supersetID: groupID, supersetOrder: 1)
        let third = makeActiveExercise(id: UUID(), order: 2, supersetID: groupID, supersetOrder: 2)
        var exerciseIndex = 0
        var setIndex = 0
        var threeMembers = [first, second, third]

        WatchWorkoutStructuralReducer.remove(
            slotID: second.id,
            from: &threeMembers,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(threeMembers.map(\.supersetOrder) == [0, 1])
        #expect(threeMembers.allSatisfy { $0.supersetId == groupID })

        WatchWorkoutStructuralReducer.remove(
            slotID: third.id,
            from: &threeMembers,
            currentExerciseIndex: &exerciseIndex,
            currentSetIndex: &setIndex
        )
        #expect(threeMembers[0].supersetId == nil)
        #expect(threeMembers[0].supersetOrder == 0)
    }

    @Test
    func progressSegmentsKeepSlotIdentityAcrossRemoval() {
        let first = makeActiveExercise(id: UUID(), order: 0, setCompleted: true)
        let second = makeActiveExercise(id: UUID(), order: 1)

        #expect(WatchWorkoutStructuralReducer.progressSegments(for: [first, second]) == [
            .init(id: first.id, fraction: 1),
            .init(id: second.id, fraction: 0)
        ])
        #expect(WatchWorkoutStructuralReducer.progressSegments(for: [second]) == [
            .init(id: second.id, fraction: 0)
        ])
    }
}
