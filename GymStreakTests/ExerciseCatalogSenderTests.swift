//
//  ExerciseCatalogSenderTests.swift
//  GymStreakTests
//
//  Covers the iOS sender state machine (challenge gating, authority
//  handover/promotion, generation high-water recovery, duplicate suppression,
//  failure classification, relaunch reuse) with a recording transport and a
//  per-test temp directory, plus the ExercisesViewModel/coordinator sync
//  triggers against real in-memory repositories.
//

import Testing
import Foundation
import WatchConnectivity
import SwiftData
@testable import GymStreak

// MARK: - Doubles

@MainActor
private final class MockCatalogTransport: ExerciseCatalogTransporting {
    var isReadyForCatalogTransfer = true
    private(set) var cancelCalls = 0
    private(set) var transferredSnapshots: [WatchExerciseCatalogSnapshot] = []
    private(set) var lastFileURL: URL?
    private(set) var lastMetadata: [String: Any]?

    func cancelOutstandingCatalogTransfers() {
        cancelCalls += 1
    }

    func transferCatalogFile(at url: URL, metadata: [String: Any]) {
        lastFileURL = url
        lastMetadata = metadata
        // Decode immediately — the sender may legitimately clean the file up later.
        if let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(WatchExerciseCatalogSnapshot.self, from: data) {
            transferredSnapshots.append(snapshot)
        }
    }
}

@MainActor
private final class MockCatalogSyncRequester: ExerciseCatalogSyncRequesting {
    private(set) var requestCount = 0
    func requestCatalogSync() { requestCount += 1 }
}

/// Wraps a real repository but fails every save — verifies that no sync is
/// requested for state that never committed.
@MainActor
private final class FailingSaveExerciseRepository: ExerciseRepository {
    struct SaveError: Error {}
    private let wrapped: ExerciseRepository
    init(wrapping repository: ExerciseRepository) { self.wrapped = repository }

    func fetchAll() -> [Exercise] { wrapped.fetchAll() }
    func fetch(id: UUID) -> Exercise? { wrapped.fetch(id: id) }
    func insert(_ exercise: Exercise) { wrapped.insert(exercise) }
    func delete(_ exercise: Exercise) { wrapped.delete(exercise) }
    func save() throws { throw SaveError() }
}

// MARK: - Helpers

private func makeItems(_ names: [String]) -> [WatchExerciseCatalogItem] {
    names.map {
        WatchExerciseCatalogItem(
            id: UUID(),
            seedKey: nil,
            name: $0,
            muscleGroups: ["Chest"],
            equipmentTypeRaw: "barbell",
            loadBehaviorRaw: "resistance"
        )
    }
}

private func challengeContext(
    watch: UUID,
    epoch: UUID?,
    generation: UInt64,
    nonce: UUID
) -> [String: Any] {
    var context: [String: Any] = [
        WatchExerciseCatalogSync.contextWatchInstanceIDKey: watch.uuidString,
        WatchExerciseCatalogSync.contextCurrentGenerationKey: String(generation),
        WatchExerciseCatalogSync.contextHandoverNonceKey: nonce.uuidString
    ]
    if let epoch {
        context[WatchExerciseCatalogSync.contextCurrentEpochKey] = epoch.uuidString
    }
    return context
}

private func wcError(_ code: WCError.Code) -> Error {
    NSError(domain: WCError.errorDomain, code: code.rawValue)
}

// MARK: - Sender

@MainActor
struct ExerciseCatalogSenderTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-sender-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test
    func withoutChallengeNothingIsSentButDesiredStateIsRetained() {
        let transport = MockCatalogTransport()
        let directory = makeTempDirectory()
        let sender = ExerciseCatalogSender(transport: transport, directory: directory)

        sender.requestSync(items: makeItems(["Bench Press"]))

        #expect(transport.transferredSnapshots.isEmpty)
        #expect(sender.state.desiredItems?.count == 1)

        // The challenge arriving later releases the retained desired state.
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        ))
        #expect(transport.transferredSnapshots.count == 1)
    }

    @Test
    func bootstrapChallengeProducesTargetedHandoverSnapshot() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())
        let watch = UUID()
        let nonce = UUID()
        let items = makeItems(["Bench Press", "Squat"])

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: nil, generation: 0, nonce: nonce
        ))
        sender.requestSync(items: items)

        let snapshot = try #require(transport.transferredSnapshots.last)
        #expect(snapshot.schemaVersion == WatchExerciseCatalogSync.schemaVersion)
        #expect(snapshot.generation == 1)
        #expect(snapshot.targetWatchInstanceID == watch)
        #expect(snapshot.fromAuthorityEpoch == nil)
        #expect(snapshot.handoverNonce == nonce)
        #expect(snapshot.items == items)
        #expect(transport.cancelCalls == 1)
        #expect(transport.lastMetadata?[WatchExerciseCatalogSync.metadataTypeKey] as? String
            == WatchExerciseCatalogSync.metadataTypeValue)
    }

    @Test
    func promotionSwitchesToUntargetedSameAuthoritySnapshots() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())
        let watch = UUID()

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["Bench Press"]))
        let handover = try #require(transport.transferredSnapshots.last)

        // Watch accepted: it republishes the proposed epoch as current.
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: handover.authorityEpoch, generation: handover.generation, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["Bench Press", "Deadlift"]))

        let next = try #require(transport.transferredSnapshots.last)
        #expect(next.authorityEpoch == handover.authorityEpoch)
        #expect(next.generation == handover.generation + 1)
        #expect(next.targetWatchInstanceID == nil)
        #expect(next.fromAuthorityEpoch == nil)
        #expect(next.handoverNonce == nil)
    }

    @Test
    func identicalChallengesLogOnceWithoutSkippingSyncProcessing() {
        let transport = MockCatalogTransport()
        var challengeLogs: [String] = []
        let sender = ExerciseCatalogSender(
            transport: transport,
            directory: makeTempDirectory(),
            challengeLogger: { challengeLogs.append($0) }
        )
        let items = makeItems(["Bench Press"])
        let context = challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        )

        sender.updateChallenge(fromApplicationContext: context)
        sender.updateChallenge(fromApplicationContext: context)
        sender.requestSync(items: items)
        sender.requestSync(items: items)
        sender.sessionDidBecomeReady()

        #expect(challengeLogs.count == 1)
        #expect(transport.transferredSnapshots.count == 1)
    }

    @Test
    func receiverHighWaterMarkRecoversRestoredSenderState() throws {
        let transport = MockCatalogTransport()
        let directory = makeTempDirectory()
        let sender = ExerciseCatalogSender(transport: transport, directory: directory)
        let watch = UUID()

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))
        let epoch = try #require(transport.transferredSnapshots.last).authorityEpoch

        // The watch reports the shared epoch at generation 9 (e.g. this iOS
        // state was restored from an older backup at a lower counter).
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: epoch, generation: 9, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A", "B"]))

        let next = try #require(transport.transferredSnapshots.last)
        #expect(next.authorityEpoch == epoch)
        #expect(next.generation == 10)
    }

    @Test
    func relaunchReenqueuesTheExactPersistedSnapshot() throws {
        let directory = makeTempDirectory()
        let watch = UUID()
        let nonce = UUID()
        let context = challengeContext(watch: watch, epoch: nil, generation: 0, nonce: nonce)
        let items = makeItems(["Bench Press"])

        let transport1 = MockCatalogTransport()
        let sender1 = ExerciseCatalogSender(transport: transport1, directory: directory)
        sender1.updateChallenge(fromApplicationContext: context)
        sender1.requestSync(items: items)
        let original = try #require(transport1.transferredSnapshots.last)

        // Simulated relaunch: fresh sender, same persisted state, same challenge.
        let transport2 = MockCatalogTransport()
        let sender2 = ExerciseCatalogSender(transport: transport2, directory: directory)
        sender2.updateChallenge(fromApplicationContext: context)
        sender2.sessionDidBecomeReady()

        let resent = try #require(transport2.transferredSnapshots.last)
        #expect(resent.snapshotID == original.snapshotID)
        #expect(resent.authorityEpoch == original.authorityEpoch)
        #expect(resent.generation == original.generation)
    }

    @Test
    func changedChallengeTupleAllocatesFreshProposedAuthority() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))
        let first = try #require(transport.transferredSnapshots.last)

        // A different watch instance (reinstall/switch) publishes its own
        // bootstrap challenge — the old proposal must not be reused.
        let newWatch = UUID()
        let newNonce = UUID()
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: newWatch, epoch: nil, generation: 0, nonce: newNonce
        ))

        let second = try #require(transport.transferredSnapshots.last)
        #expect(second.authorityEpoch != first.authorityEpoch)
        #expect(second.targetWatchInstanceID == newWatch)
        #expect(second.handoverNonce == newNonce)
    }

    @Test
    func retiredAuthorityMintsFreshEpochForTheReportedChallenge() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())
        let watch = UUID()

        // Establish an active authority (bootstrap + watch confirmation).
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))
        let established = try #require(transport.transferredSnapshots.last)
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: established.authorityEpoch, generation: established.generation, nonce: UUID()
        ))

        // The watch is meanwhile on a different (unknown to us) epoch E3 —
        // e.g. our persisted authority was retired while this iOS state was in
        // a backup. A fresh E4 must be minted for the E3 challenge; the
        // retired epoch is never retried.
        let watchEpoch = UUID()
        let nonce = UUID()
        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: watch, epoch: watchEpoch, generation: 4, nonce: nonce
        ))

        let handover = try #require(transport.transferredSnapshots.last)
        #expect(handover.authorityEpoch != established.authorityEpoch)
        #expect(handover.authorityEpoch != watchEpoch)
        #expect(handover.fromAuthorityEpoch == watchEpoch)
        #expect(handover.handoverNonce == nonce)
        #expect(handover.targetWatchInstanceID == watch)
    }

    @Test
    func transientFailureKeepsSnapshotReplayableThroughLifecycleTriggers() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))
        let snapshot = try #require(transport.transferredSnapshots.last)
        let fileURL = try #require(transport.lastFileURL)

        sender.transferDidFinish(fileURL: fileURL, snapshotID: snapshot.snapshotID, error: wcError(.sessionNotActivated))
        sender.sessionDidBecomeReady()

        #expect(transport.transferredSnapshots.count == 2)
        #expect(transport.transferredSnapshots.last?.snapshotID == snapshot.snapshotID)
    }

    @Test
    func terminalFailureBlocksTheBytesUntilContentChanges() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))
        let snapshot = try #require(transport.transferredSnapshots.last)
        let fileURL = try #require(transport.lastFileURL)

        sender.transferDidFinish(fileURL: fileURL, snapshotID: snapshot.snapshotID, error: wcError(.payloadTooLarge))

        // Lifecycle triggers must not hot-loop the poison payload…
        sender.sessionDidBecomeReady()
        #expect(transport.transferredSnapshots.count == 1)

        // …but changed catalogue content unblocks with a fresh snapshot.
        sender.requestSync(items: makeItems(["A", "B"]))
        #expect(transport.transferredSnapshots.count == 2)
        #expect(transport.transferredSnapshots.last?.snapshotID != snapshot.snapshotID)
    }

    @Test
    func supersededSnapshotFailureNeverRequeuesItself() throws {
        let transport = MockCatalogTransport()
        let sender = ExerciseCatalogSender(transport: transport, directory: makeTempDirectory())

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))
        let first = try #require(transport.transferredSnapshots.last)
        let firstURL = try #require(transport.lastFileURL)

        sender.requestSync(items: makeItems(["A", "B"])) // supersedes + cancels first
        #expect(transport.transferredSnapshots.count == 2)

        // The cancelled first transfer reports back with an error.
        sender.transferDidFinish(fileURL: firstURL, snapshotID: first.snapshotID, error: wcError(.genericError))
        sender.sessionDidBecomeReady()

        // Rapid A → B converged to B; the superseded A never re-enqueued.
        #expect(transport.transferredSnapshots.count == 2)
        #expect(transport.transferredSnapshots.last?.items.count == 2)
    }

    @Test
    func stateWriteFailureEnqueuesNothing() {
        let transport = MockCatalogTransport()
        // A directory path that cannot exist: nested under a regular file.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        let sender = ExerciseCatalogSender(
            transport: transport,
            directory: blocker.appendingPathComponent("nested", isDirectory: true)
        )

        sender.updateChallenge(fromApplicationContext: challengeContext(
            watch: UUID(), epoch: nil, generation: 0, nonce: UUID()
        ))
        sender.requestSync(items: makeItems(["A"]))

        #expect(transport.transferredSnapshots.isEmpty)
    }
}

// MARK: - ViewModel + coordinator triggers

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory
// ModelContainer creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct ExerciseCatalogSyncTriggerTests {

    private func makeViewModel(
        failSaves: Bool = false
    ) -> (viewModel: ExercisesViewModel, catalogSync: MockCatalogSyncRequester) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        var exerciseRepository: ExerciseRepository = SwiftDataExerciseRepository(modelContext: context)
        if failSaves {
            exerciseRepository = FailingSaveExerciseRepository(wrapping: exerciseRepository)
        }
        let catalogSync = MockCatalogSyncRequester()
        let viewModel = ExercisesViewModel(
            exerciseRepository: exerciseRepository,
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            catalogSync: catalogSync
        )
        return (viewModel, catalogSync)
    }

    @Test
    func eachSuccessfulMutationRequestsExactlyOneSync() {
        let (viewModel, catalogSync) = makeViewModel()

        let exercise = viewModel.addExercise(name: "Bench Press", muscleGroups: ["Chest"])
        #expect(catalogSync.requestCount == 1)

        viewModel.updateExercise(exercise!)
        #expect(catalogSync.requestCount == 2)

        viewModel.requestDeleteExercise(exercise!)
        viewModel.confirmDeleteExercise()
        #expect(catalogSync.requestCount == 3)

        _ = viewModel.addExercise(name: "Squat", muscleGroups: ["Legs"])
        viewModel.confirmDeleteAllExercises()
        #expect(catalogSync.requestCount == 5)

        // Ordinary fetches never request a sync.
        viewModel.fetchExercises()
        #expect(catalogSync.requestCount == 5)
    }

    @Test
    func failedSaveRequestsNoSync() {
        let (viewModel, catalogSync) = makeViewModel(failSaves: true)

        _ = viewModel.addExercise(name: "Bench Press", muscleGroups: ["Chest"])

        #expect(catalogSync.requestCount == 0)
    }

    @Test
    func coordinatorFetchesCurrentRepositoryState() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let repository = SwiftDataExerciseRepository(modelContext: context)
        let watchSync = MockWatchSyncServicing()
        let coordinator = ExerciseCatalogSyncCoordinator(
            exerciseRepository: repository,
            watchSync: watchSync
        )

        // Post-seed trigger carries the (seeded) library.
        repository.insert(Exercise(name: "Seeded Bench Press"))
        try repository.save()
        coordinator.requestCatalogSync()
        #expect(watchSync.syncExerciseCatalogCalls.count == 1)
        #expect(watchSync.syncExerciseCatalogCalls.last?.map(\.name) == ["Seeded Bench Press"])

        // CloudKit change trigger re-fetches fresh committed state.
        repository.insert(Exercise(name: "Cloud Row"))
        try repository.save()
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
        // The observer hops onto the main actor via a Task; yield until it ran.
        for _ in 0..<100 where watchSync.syncExerciseCatalogCalls.count < 2 {
            await Task.yield()
        }
        #expect(watchSync.syncExerciseCatalogCalls.count == 2)
        #expect(watchSync.syncExerciseCatalogCalls.last?.count == 2)
    }
}
