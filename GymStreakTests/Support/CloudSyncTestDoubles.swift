//
//  CloudSyncTestDoubles.swift
//  GymStreakTests
//
//  Shared doubles for `CloudSyncStatusProviding`. Anything that waits on iCloud
//  before touching the store — `DefaultContentSeeder`'s stranded-library
//  recovery, `RoutinePlanLinkRepair` — needs to be driven by a scripted status
//  rather than a real CloudKit monitor.
//

import Foundation
@testable import GymStreak

/// Feeds a consumer a scripted sync status; `emit` drives any wait it performs.
@MainActor
final class StubCloudSyncStatus: CloudSyncStatusProviding {
    private(set) var currentStatus: CloudSyncStatus = CloudSyncStatus(
        state: .syncing,
        lastSuccessfulSync: nil
    )
    private var continuations: [UUID: AsyncStream<CloudSyncStatus>.Continuation] = [:]
    private var subscriberWaiters: [CheckedContinuation<Void, Never>] = []

    init(initial: CloudSyncStatus = CloudSyncStatus(state: .syncing, lastSuccessfulSync: nil)) {
        self.currentStatus = initial
    }

    /// A store that has already completed a transfer — the state in which
    /// touching rows is safe.
    static func synced() -> StubCloudSyncStatus {
        StubCloudSyncStatus(
            initial: CloudSyncStatus(state: .upToDate, lastSuccessfulSync: Date())
        )
    }

    func statusUpdates() -> AsyncStream<CloudSyncStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(currentStatus)
            for waiter in subscriberWaiters { waiter.resume() }
            subscriberWaiters.removeAll()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// Suspends until a consumer has subscribed, so a test can `emit` without
    /// racing the consumer's subscription — `Task.yield()` does not guarantee the
    /// consumer got that far, and an `emit` that lands first is dropped, leaving
    /// the consumer awaiting forever.
    func waitForSubscriber() async {
        guard continuations.isEmpty else { return }
        await withCheckedContinuation { subscriberWaiters.append($0) }
    }

    func emit(_ status: CloudSyncStatus) {
        currentStatus = status
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }
}
