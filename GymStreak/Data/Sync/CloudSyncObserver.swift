import Foundation
import CoreData
import Combine
import OSLog

/// Legacy notification name posted when the persistent store reports a remote change.
extension Notification.Name {
    static let cloudKitDataDidChange = Notification.Name("cloudKitDataDidChange")
}

/// Observes persistent-store remote-change events and notifies subscribers.
/// This is a singleton that should be initialized once at app startup.
///
/// **Remote changes arrive in bursts, and the fan-out is expensive.** Four
/// long-lived handlers listen to `.cloudKitDataDidChange` — `RoutinesViewModel`,
/// `ExercisesViewModel` and `WorkoutViewModel` each refetch, and
/// `ExerciseCatalogSyncCoordinator` refetches the whole exercise library before
/// handing it to the watch — so one notification costs four main-actor
/// SwiftData fetches. A bulk import (new device, reinstall, or a
/// `ServerChangeTokenExpired` reset that re-downloads the private database)
/// posts well over a hundred of them in a single session, which is exactly the
/// window in which the app should feel fastest.
///
/// The refreshes themselves are correct and idempotent; only their frequency is
/// wrong, so the fix lives here at the single source rather than in the four
/// consumers. Fan-outs are coalesced **leading-edge first**: the first change
/// after a quiet period fans out immediately, and everything arriving inside the
/// following window collapses into one trailing fan-out. A burst therefore costs
/// at most one fan-out per window instead of one per notification, while an
/// isolated change — the steady-state case — is never delayed at all.
@MainActor
final class CloudSyncObserver: ObservableObject {
    static let shared = CloudSyncObserver()

    /// Published property that increments on each sync event, allowing views to react
    @Published private(set) var syncVersion: Int = 0

    /// Shortest gap between two consecutive fan-outs during a burst.
    ///
    /// Two seconds sits above the sub-second spacing of the notifications inside
    /// one CloudKit import batch, so a batch collapses to a single refresh, and
    /// far below CloudKit's own end-to-end delivery latency for a change made on
    /// another device — which is already many seconds — so the added delay is
    /// invisible against the transport it is throttling. It only ever applies to
    /// a change that lands within the window of a previous one; the first change
    /// of any quiet period is fanned out synchronously.
    static let defaultCoalescingWindow: Duration = .seconds(2)

    private static let logger = Logger(
        subsystem: LogSubsystem.sync,
        category: "RemoteChange"
    )

    private let coalescingWindow: Duration
    private var notificationObserver: NSObjectProtocol?
    private var coalescingTask: Task<Void, Never>?
    private var hasChangeAwaitingFanOut = false

    /// Internal rather than private only so tests can drive a window short
    /// enough to assert against. Production always goes through `shared`.
    init(coalescingWindow: Duration = CloudSyncObserver.defaultCoalescingWindow) {
        self.coalescingWindow = coalescingWindow
        setupRemoteChangeObserver()
    }

    private func setupRemoteChangeObserver() {
        // This Core Data notification is not exclusive to CloudKit.
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRemoteChange()
            }
        }
    }

    private func handleRemoteChange() {
        // `.debug` is not written to the on-disk log store, so this costs
        // nothing in release and is still readable from a live `log stream`.
        Self.logger.debug("Persistent store change detected")

        guard coalescingTask == nil else {
            // A fan-out already went out inside the open window; fold this
            // change into the single trailing one.
            hasChangeAwaitingFanOut = true
            return
        }

        fanOutSyncEvent()
        openCoalescingWindow()
    }

    /// Re-arms for as long as changes keep arriving — emitting at most one
    /// fan-out per window — and closes once a whole window passes with nothing
    /// pending, so the next isolated change is immediate again.
    private func openCoalescingWindow() {
        let window = coalescingWindow
        coalescingTask = Task { @MainActor [weak self] in
            while true {
                guard (try? await Task.sleep(for: window)) != nil else { break }
                guard let self, hasChangeAwaitingFanOut else { break }
                hasChangeAwaitingFanOut = false
                fanOutSyncEvent()
            }
            self?.coalescingTask = nil
        }
    }

    private func fanOutSyncEvent() {
        syncVersion += 1

        // Post notification for ViewModels that prefer notification-based updates
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
    }

    /// `isolated deinit` (SE-0371): `notificationObserver` is a non-`Sendable`
    /// `NSObjectProtocol`, which a nonisolated `deinit` may not touch under strict
    /// concurrency. Isolating the deinit to this class's main actor lets it read
    /// its own stored state, which is what the teardown actually needs.
    isolated deinit {
        coalescingTask?.cancel()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
