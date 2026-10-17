//
//  WatchSummarySyncStatusTests.swift
//  GymStreakWatchTests
//
//  positioning-usp ticket 03 (docs/watch-sync.md, "Showing the guarantee on
//  the summary"): the watch summary's "Saved on iPhone" status is driven by the
//  workout's HISTORY entry in the durable queue — never by its template intent.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchSummarySyncStatusTests {

    // MARK: - Mapping

    @Test(arguments: [OutgoingWorkoutPhase.awaitingHealthKitMetadata, .awaitingHealthKitFinish, .transportEligible])
    func queuedEntryIsSavingWhenPhoneIsReachable(phase: OutgoingWorkoutPhase) {
        #expect(WatchSummarySyncStatus.resolve(historyPhase: phase, isPhoneReachable: true) == .saving)
    }

    @Test(arguments: [OutgoingWorkoutPhase.awaitingHealthKitMetadata, .awaitingHealthKitFinish, .transportEligible])
    func queuedEntryReassuresWhenPhoneIsUnreachable(phase: OutgoingWorkoutPhase) {
        #expect(WatchSummarySyncStatus.resolve(historyPhase: phase, isPhoneReachable: false) == .waitingForPhone)
    }

    @Test(arguments: [true, false])
    func retiredEntryIsSavedRegardlessOfReachability(isPhoneReachable: Bool) {
        #expect(WatchSummarySyncStatus.resolve(historyPhase: nil, isPhoneReachable: isPhoneReachable) == .saved)
    }

    @Test(arguments: [true, false])
    func quarantinedEntryIsNotSent(isPhoneReachable: Bool) {
        #expect(WatchSummarySyncStatus.resolve(historyPhase: .quarantined, isPhoneReachable: isPhoneReachable) == .notSent)
    }

    // MARK: - Queue state → status

    private func makeStore() -> WatchSyncStateStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return WatchSyncStateStore(directory: directory)
    }

    private func workout(updatesTemplate: Bool) -> CompletedWatchWorkout {
        CompletedWatchWorkout(
            id: UUID(),
            routineId: UUID(),
            routineName: "Push",
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_003_600),
            exercises: [],
            shouldUpdateTemplate: updatesTemplate,
            healthKitWorkoutId: UUID()
        )
    }

    private func status(of workoutID: UUID, in store: WatchSyncStateStore) -> WatchSummarySyncStatus {
        WatchSummarySyncStatus.resolve(historyPhase: store.entry(id: workoutID)?.phase, isPhoneReachable: true)
    }

    @Test
    func acknowledgmentTurnsSavingIntoSaved() throws {
        let store = makeStore()
        let workout = workout(updatesTemplate: false)
        try store.enqueue(workout, phase: .transportEligible)
        #expect(status(of: workout.id, in: store) == .saving)

        store.acknowledgePlain(workoutId: workout.id)

        #expect(status(of: workout.id, in: store) == .saved)
    }

    @Test
    func pendingTemplateIntentDoesNotHoldBackSavedHistory() throws {
        let store = makeStore()
        let workout = workout(updatesTemplate: true)
        try store.enqueue(workout, phase: .transportEligible)

        store.acknowledgePlain(workoutId: workout.id)

        // The template half is still queued, unacknowledged.
        #expect(store.all.contains { $0.templateTransaction != nil })
        #expect(status(of: workout.id, in: store) == .saved)
    }

    @Test
    func quarantinedTemplateIntentDoesNotMakeHistoryLookUnsaved() throws {
        let store = makeStore()
        let workout = workout(updatesTemplate: true)
        try store.enqueue(workout, phase: .transportEligible)
        let templateID = try #require(store.all.first { $0.templateTransaction != nil }?.id)

        store.quarantine(id: templateID, reason: "test")

        #expect(status(of: workout.id, in: store) == .saving)
        store.acknowledgePlain(workoutId: workout.id)
        #expect(status(of: workout.id, in: store) == .saved)
    }
}
