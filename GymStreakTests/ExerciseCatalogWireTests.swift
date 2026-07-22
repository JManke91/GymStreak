//
//  ExerciseCatalogWireTests.swift
//  GymStreakTests
//
//  Covers the exercise-catalogue wire mapping and the receiver acceptance
//  state machine (WatchExerciseCatalogReceiverState). The watch target has no
//  unit-test target, so the receiver rules are tested through the identical
//  iOS copy of WatchExerciseCatalogModels.swift.
//

import Testing
import Foundation
@testable import GymStreak

// MARK: - Mapper

struct WatchExerciseCatalogMapperTests {

    @Test
    func mappingPreservesAllFields() {
        let exercise = Exercise(
            name: "Lat Pulldown",
            muscleGroups: ["Back", "Biceps"],
            equipmentType: .machine,
            loadBehavior: .counterweightAssistance
        )
        exercise.seedKey = "seed.exercise.lat_pulldown"

        let items = WatchExerciseCatalogMapper.items(from: [exercise])

        #expect(items.count == 1)
        let item = items[0]
        #expect(item.id == exercise.id)
        #expect(item.seedKey == "seed.exercise.lat_pulldown")
        #expect(item.name == "Lat Pulldown")
        #expect(item.muscleGroups == ["Back", "Biceps"])
        #expect(item.equipmentTypeRaw == exercise.equipmentTypeRaw)
        #expect(item.loadBehaviorRaw == exercise.loadBehaviorRaw)
    }

    @Test
    func emptySeedKeyMapsToNil() {
        let custom = Exercise(name: "My Custom Curl")
        let items = WatchExerciseCatalogMapper.items(from: [custom])
        #expect(items[0].seedKey == nil)
    }

    @Test
    func orderingIsCaseInsensitiveWithUUIDTieBreaker() {
        let banana = Exercise(name: "banana press")
        let apple = Exercise(name: "Apple row")
        let cherry = Exercise(name: "Cherry curl")
        let sameA = Exercise(name: "Same Name")
        let sameB = Exercise(name: "Same Name")

        let items = WatchExerciseCatalogMapper.items(from: [sameB, banana, cherry, sameA, apple])

        #expect(items.map(\.name) == ["Apple row", "banana press", "Cherry curl", "Same Name", "Same Name"])
        let tied = items.filter { $0.name == "Same Name" }
        #expect(tied.map(\.id.uuidString) == tied.map(\.id.uuidString).sorted())

        // Deterministic: mapping a shuffled copy produces the identical order.
        let again = WatchExerciseCatalogMapper.items(from: [apple, sameA, banana, sameB, cherry])
        #expect(again == items)
    }
}

// MARK: - Receiver state machine

struct WatchExerciseCatalogReceiverStateTests {

    private func makeItem(name: String = "Bench Press") -> WatchExerciseCatalogItem {
        WatchExerciseCatalogItem(
            id: UUID(),
            seedKey: nil,
            name: name,
            muscleGroups: ["Chest"],
            equipmentTypeRaw: "barbell",
            loadBehaviorRaw: "resistance"
        )
    }

    private func handoverSnapshot(
        to state: WatchExerciseCatalogReceiverState,
        epoch: UUID = UUID(),
        generation: UInt64 = 1,
        items: [WatchExerciseCatalogItem] = []
    ) -> WatchExerciseCatalogSnapshot {
        WatchExerciseCatalogSnapshot(
            schemaVersion: WatchExerciseCatalogSync.schemaVersion,
            authorityEpoch: epoch,
            generation: generation,
            snapshotID: UUID(),
            targetWatchInstanceID: state.watchInstanceID,
            fromAuthorityEpoch: state.acceptedEpoch,
            handoverNonce: state.handoverNonce,
            items: items
        )
    }

    private func sameEpochSnapshot(
        epoch: UUID,
        generation: UInt64,
        items: [WatchExerciseCatalogItem] = []
    ) -> WatchExerciseCatalogSnapshot {
        WatchExerciseCatalogSnapshot(
            schemaVersion: WatchExerciseCatalogSync.schemaVersion,
            authorityEpoch: epoch,
            generation: generation,
            snapshotID: UUID(),
            targetWatchInstanceID: nil,
            fromAuthorityEpoch: nil,
            handoverNonce: nil,
            items: items
        )
    }

    @Test
    func bootstrapHandoverIsAcceptedAndCommitsAtomicallyModeledState() {
        var state = WatchExerciseCatalogReceiverState.initial()
        let originalNonce = state.handoverNonce
        let item = makeItem()
        let snapshot = handoverSnapshot(to: state, generation: 1, items: [item])

        #expect(state.decision(for: snapshot) == .apply(isHandover: true))
        state.accept(snapshot, isHandover: true, at: Date())

        #expect(state.acceptedEpoch == snapshot.authorityEpoch)
        #expect(state.acceptedGeneration == 1)
        #expect(state.items == [item])
        #expect(state.hasReceivedCatalog)
        #expect(state.lastSnapshotID == snapshot.snapshotID)
        // The one-shot nonce is consumed and re-minted in the same commit.
        #expect(state.handoverNonce != originalNonce)
    }

    @Test
    func sameEpochRequiresStrictlyHigherGeneration() {
        var state = WatchExerciseCatalogReceiverState.initial()
        let bootstrap = handoverSnapshot(to: state, generation: 5)
        state.accept(bootstrap, isHandover: true, at: Date())
        let epoch = bootstrap.authorityEpoch

        #expect(state.decision(for: sameEpochSnapshot(epoch: epoch, generation: 6)) == .apply(isHandover: false))
        #expect(state.decision(for: sameEpochSnapshot(epoch: epoch, generation: 4)) == .reject(.staleGeneration))
        // Equal generation but different content cannot be ordered — rejected.
        #expect(state.decision(for: sameEpochSnapshot(epoch: epoch, generation: 5)) == .reject(.conflictingEqualGeneration))
    }

    @Test
    func duplicateSnapshotIsIdempotent() {
        var state = WatchExerciseCatalogReceiverState.initial()
        let snapshot = handoverSnapshot(to: state, items: [makeItem()])
        state.accept(snapshot, isHandover: true, at: Date())

        #expect(state.decision(for: snapshot) == .duplicate)
    }

    @Test
    func unauthorizedHandoversAreRejected() {
        let state = WatchExerciseCatalogReceiverState.initial()

        // Wrong target watch instance.
        var wrongTarget = handoverSnapshot(to: state)
        wrongTarget = WatchExerciseCatalogSnapshot(
            schemaVersion: wrongTarget.schemaVersion,
            authorityEpoch: wrongTarget.authorityEpoch,
            generation: wrongTarget.generation,
            snapshotID: wrongTarget.snapshotID,
            targetWatchInstanceID: UUID(),
            fromAuthorityEpoch: wrongTarget.fromAuthorityEpoch,
            handoverNonce: wrongTarget.handoverNonce,
            items: []
        )
        #expect(state.decision(for: wrongTarget) == .reject(.wrongTargetWatch))

        // Wrong from-epoch (claims to move away from an epoch we never had).
        let wrongFrom = WatchExerciseCatalogSnapshot(
            schemaVersion: WatchExerciseCatalogSync.schemaVersion,
            authorityEpoch: UUID(),
            generation: 1,
            snapshotID: UUID(),
            targetWatchInstanceID: state.watchInstanceID,
            fromAuthorityEpoch: UUID(),
            handoverNonce: state.handoverNonce,
            items: []
        )
        #expect(state.decision(for: wrongFrom) == .reject(.wrongFromEpoch))

        // Wrong (or already consumed) nonce.
        let wrongNonce = WatchExerciseCatalogSnapshot(
            schemaVersion: WatchExerciseCatalogSync.schemaVersion,
            authorityEpoch: UUID(),
            generation: 1,
            snapshotID: UUID(),
            targetWatchInstanceID: state.watchInstanceID,
            fromAuthorityEpoch: nil,
            handoverNonce: UUID(),
            items: []
        )
        #expect(state.decision(for: wrongNonce) == .reject(.wrongNonce))
    }

    @Test
    func retiredEpochCanNeverBeRestored() {
        var state = WatchExerciseCatalogReceiverState.initial()
        let epoch1 = handoverSnapshot(to: state, generation: 3)
        state.accept(epoch1, isHandover: true, at: Date())
        let retired = epoch1.authorityEpoch

        let epoch2 = handoverSnapshot(to: state, generation: 1)
        state.accept(epoch2, isHandover: true, at: Date())

        // A late E1 file — even with a huge generation — is rejected forever.
        #expect(state.decision(for: sameEpochSnapshot(epoch: retired, generation: 999)) == .reject(.retiredEpoch))
        #expect(state.retiredEpochs.contains(retired))
    }

    @Test
    func usedNonceIsRejectedAfterHandover() {
        var state = WatchExerciseCatalogReceiverState.initial()
        let usedNonce = state.handoverNonce
        state.accept(handoverSnapshot(to: state), isHandover: true, at: Date())

        let replayed = WatchExerciseCatalogSnapshot(
            schemaVersion: WatchExerciseCatalogSync.schemaVersion,
            authorityEpoch: UUID(),
            generation: 1,
            snapshotID: UUID(),
            targetWatchInstanceID: state.watchInstanceID,
            fromAuthorityEpoch: state.acceptedEpoch,
            handoverNonce: usedNonce,
            items: []
        )
        #expect(state.decision(for: replayed) == .reject(.wrongNonce))
    }

    @Test
    func validEmptySnapshotClearsItemsButStaysReceived() {
        var state = WatchExerciseCatalogReceiverState.initial()
        state.accept(handoverSnapshot(to: state, generation: 1, items: [makeItem()]), isHandover: true, at: Date())
        #expect(state.items?.isEmpty == false)

        let epoch = state.acceptedEpoch!
        let empty = sameEpochSnapshot(epoch: epoch, generation: 2, items: [])
        #expect(state.decision(for: empty) == .apply(isHandover: false))
        state.accept(empty, isHandover: false, at: Date())

        // Valid-empty is distinct from never-synced.
        #expect(state.items == [])
        #expect(state.hasReceivedCatalog)
    }

    @Test
    func unsupportedSchemaIsRejected() {
        let state = WatchExerciseCatalogReceiverState.initial()
        let future = WatchExerciseCatalogSnapshot(
            schemaVersion: WatchExerciseCatalogSync.schemaVersion + 1,
            authorityEpoch: UUID(),
            generation: 1,
            snapshotID: UUID(),
            targetWatchInstanceID: state.watchInstanceID,
            fromAuthorityEpoch: nil,
            handoverNonce: state.handoverNonce,
            items: []
        )
        #expect(state.decision(for: future) == .reject(.unsupportedSchema))
    }

    @Test
    func statePersistenceRoundTripsIncludingNeverVsEmptyDistinction() throws {
        var state = WatchExerciseCatalogReceiverState.initial()

        // Never-synced round-trip.
        var decoded = try JSONDecoder().decode(
            WatchExerciseCatalogReceiverState.self,
            from: JSONEncoder().encode(state)
        )
        #expect(!decoded.hasReceivedCatalog)
        #expect(decoded.watchInstanceID == state.watchInstanceID)
        #expect(decoded.handoverNonce == state.handoverNonce)

        // Populated round-trip.
        let snapshot = handoverSnapshot(to: state, items: [makeItem()])
        state.accept(snapshot, isHandover: true, at: Date())
        decoded = try JSONDecoder().decode(
            WatchExerciseCatalogReceiverState.self,
            from: JSONEncoder().encode(state)
        )
        #expect(decoded.hasReceivedCatalog)
        #expect(decoded.items == state.items)
        #expect(decoded.acceptedEpoch == snapshot.authorityEpoch)
        #expect(decoded.acceptedGeneration == snapshot.generation)
        #expect(decoded.lastSnapshotID == snapshot.snapshotID)
    }

    @Test
    func challengeContextPublishesAllKeysAsStrings() {
        var state = WatchExerciseCatalogReceiverState.initial()

        // Bootstrap: no epoch key yet.
        var context = state.challengeContext
        #expect(context[WatchExerciseCatalogSync.contextWatchInstanceIDKey] == state.watchInstanceID.uuidString)
        #expect(context[WatchExerciseCatalogSync.contextCurrentEpochKey] == nil)
        #expect(context[WatchExerciseCatalogSync.contextCurrentGenerationKey] == "0")
        #expect(context[WatchExerciseCatalogSync.contextHandoverNonceKey] == state.handoverNonce.uuidString)

        state.accept(handoverSnapshot(to: state, generation: 7), isHandover: true, at: Date())
        context = state.challengeContext
        #expect(context[WatchExerciseCatalogSync.contextCurrentEpochKey] == state.acceptedEpoch?.uuidString)
        #expect(context[WatchExerciseCatalogSync.contextCurrentGenerationKey] == "7")

        // The sender must be able to parse exactly what the watch publishes.
        let parsed = WatchCatalogChallenge(applicationContext: context)
        #expect(parsed?.watchInstanceID == state.watchInstanceID)
        #expect(parsed?.currentEpoch == state.acceptedEpoch)
        #expect(parsed?.currentGeneration == 7)
        #expect(parsed?.handoverNonce == state.handoverNonce)
    }
}
