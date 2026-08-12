//
//  CloudKitSyncStatusMonitor.swift
//  GymStreak
//
//  The only place that knows how iCloud sync status is derived. Combines the
//  CloudKit account status, the mirroring events of the SwiftData-created
//  NSPersistentCloudKitContainer and network reachability into the four states
//  the Settings row shows. See docs/settings-tab.md.
//

import CloudKit
import CoreData
import Foundation
import Network

/// Push-based CloudKit sync status.
///
/// Three independent signals feed the state machine:
/// 1. `CKContainer.accountStatus()`, refreshed on `.CKAccountChanged` — decides `.off`.
/// 2. `NSPersistentCloudKitContainer.eventChangedNotification` — an event without an
///    `endDate` means a transfer is in flight (`.syncing`); a finished event carries
///    `succeeded` and `error`, which separates a successful transfer from a queued one.
/// 3. `NWPathMonitor` — no network means changes can only be queued (`.waiting`).
///
/// The last successful export and import dates are persisted, so a cold launch shows a
/// real timestamp instead of waiting for the session's first event.
@MainActor
final class CloudKitSyncStatusMonitor: CloudSyncStatusProviding {

    private enum DefaultsKey {
        static let lastExport = "cloudSync.lastSuccessfulExport"
        static let lastImport = "cloudSync.lastSuccessfulImport"
    }

    private(set) var currentStatus: CloudSyncStatus {
        didSet {
            guard currentStatus != oldValue else { return }
            for continuation in continuations.values {
                continuation.yield(currentStatus)
            }
        }
    }

    /// `false` when the app fell back to a local-only store because the CloudKit
    /// container could not be built — nothing will ever sync, so the row must
    /// report `.off` rather than a stale "up to date".
    private let isCloudKitStoreEnabled: Bool
    private let defaults: UserDefaults
    private let container: CKContainer?

    /// `nil` until the first account query returns. Treated as available so the
    /// row does not flash red during launch; the query corrects it immediately.
    private var accountStatus: CKAccountStatus?
    /// Identifiers of mirroring events that have started but not finished.
    private var eventsInFlight: Set<UUID> = []
    /// Set when a finished transfer failed for a recoverable reason (queued work).
    private var hasQueuedChanges = false
    private var hasNetwork = true
    private var lastSuccessfulExport: Date?
    private var lastSuccessfulImport: Date?

    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var continuations: [UUID: AsyncStream<CloudSyncStatus>.Continuation] = [:]

    init(
        isCloudKitStoreEnabled: Bool,
        containerIdentifier: String,
        defaults: UserDefaults = .standard
    ) {
        self.isCloudKitStoreEnabled = isCloudKitStoreEnabled
        self.defaults = defaults
        self.container = isCloudKitStoreEnabled
            ? CKContainer(identifier: containerIdentifier)
            : nil
        self.lastSuccessfulExport = defaults.object(forKey: DefaultsKey.lastExport) as? Date
        self.lastSuccessfulImport = defaults.object(forKey: DefaultsKey.lastImport) as? Date
        self.currentStatus = CloudSyncStatus(
            state: isCloudKitStoreEnabled ? .upToDate : .off,
            lastSuccessfulSync: nil
        )
        self.currentStatus = makeStatus()

        guard isCloudKitStoreEnabled else { return }
        observeMirroringEvents()
        observeAccountChanges()
        observeNetworkPath()
        Task { await refreshAccountStatus() }
    }

    deinit {
        // NotificationCenter and NWPathMonitor teardown are both thread-safe;
        // capturing only these values keeps deinit off the main actor.
        let observers = observers
        let monitor = pathMonitor
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        monitor?.cancel()
    }

    // MARK: - CloudSyncStatusProviding

    func statusUpdates() -> AsyncStream<CloudSyncStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(currentStatus)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    // MARK: - Signal sources

    /// SwiftData does not hand out its `NSPersistentCloudKitContainer`, so the
    /// notification is observed unfiltered (`object: nil`) — this app has exactly
    /// one mirrored store. Posted from CloudKit's own background queue, hence
    /// `queue: .main`.
    private func observeMirroringEvents() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { return }
                MainActor.assumeIsolated {
                    self?.handle(event: event)
                }
            }
        )
    }

    private func observeAccountChanges() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.refreshAccountStatus() }
            }
        )
    }

    private func observeNetworkPath() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.hasNetwork != isSatisfied else { return }
                self.hasNetwork = isSatisfied
                self.publish()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.jmanke.gymstreak.cloudsync.path"))
        pathMonitor = monitor
    }

    private func refreshAccountStatus() async {
        guard let container else { return }
        accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
        publish()
    }

    // MARK: - State machine

    private func handle(event: NSPersistentCloudKitContainer.Event) {
        #if DEBUG
        // Whether SwiftData's container emits these events at all can only be
        // confirmed on a device signed into iCloud — this log is how that check
        // is made (see docs/settings-tab.md §"Verification record").
        print("☁️ [CloudKitSyncStatusMonitor] event type=\(event.type.rawValue) ended=\(event.endDate != nil) succeeded=\(event.succeeded) error=\(event.error.map { String(describing: $0) } ?? "none")")
        #endif

        guard let endDate = event.endDate else {
            eventsInFlight.insert(event.identifier)
            publish()
            return
        }
        eventsInFlight.remove(event.identifier)

        if event.succeeded {
            switch event.type {
            case .export:
                lastSuccessfulExport = endDate
                defaults.set(endDate, forKey: DefaultsKey.lastExport)
                // A completed export means nothing is left queued.
                hasQueuedChanges = false
            case .import:
                lastSuccessfulImport = endDate
                defaults.set(endDate, forKey: DefaultsKey.lastImport)
            case .setup:
                break
            @unknown default:
                break
            }
        } else {
            if event.type == .export {
                hasQueuedChanges = true
            }
            if let error = event.error as? CKError, isAccountProblem(error) {
                // An authentication/permission failure may mean the account went
                // away since the last query. Re-ask CloudKit rather than pinning a
                // synthetic "signed out" for the rest of the session — a transient
                // failure then heals itself on the next event.
                Task { await refreshAccountStatus() }
            }
        }

        publish()
    }

    private func isAccountProblem(_ error: CKError) -> Bool {
        switch error.code {
        case .notAuthenticated, .managedAccountRestricted, .permissionFailure:
            true
        default:
            false
        }
    }

    private func publish() {
        currentStatus = makeStatus()
    }

    private func makeStatus() -> CloudSyncStatus {
        CloudSyncStatus(state: makeState(), lastSuccessfulSync: lastSuccessfulSync)
    }

    private func makeState() -> CloudSyncState {
        guard isCloudKitStoreEnabled else { return .off }
        // `nil` = not yet queried; every known non-available status means the
        // user's data is not going anywhere.
        if let accountStatus, accountStatus != .available { return .off }
        if !eventsInFlight.isEmpty { return .syncing }
        if !hasNetwork || hasQueuedChanges { return .waiting }
        return .upToDate
    }

    private var lastSuccessfulSync: Date? {
        switch (lastSuccessfulExport, lastSuccessfulImport) {
        case let (export?, `import`?): max(export, `import`)
        case let (export?, nil): export
        case let (nil, `import`?): `import`
        case (nil, nil): nil
        }
    }
}
