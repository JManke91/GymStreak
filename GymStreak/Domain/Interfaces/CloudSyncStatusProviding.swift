//
//  CloudSyncStatusProviding.swift
//  GymStreak
//
//  Domain-facing view of the iCloud sync state shown in Settings.
//  Implemented in Data by `CloudKitSyncStatusMonitor` — see docs/settings-tab.md.
//

import Foundation

/// The five states the Settings iCloud row distinguishes.
enum CloudSyncState: Sendable, Equatable {
    /// Everything the app knows about has been exported and imported successfully.
    case upToDate
    /// A transfer is in flight right now.
    case syncing
    /// Changes are queued but the last transfer failed for a recoverable reason
    /// (typically no network).
    case waiting
    /// Sync is broken in a way that will not heal on its own: the CloudKit store
    /// could not be built and the app fell back to local-only storage, or an
    /// export was rejected for a reason a retry cannot fix (a schema mismatch,
    /// for instance). Distinct from `.waiting`, which is a transfer that will be
    /// retried, and from `.off`, which the user can fix by signing in.
    case failing
    /// iCloud is not available for this app: signed out or restricted.
    case off
}

/// Sync state plus the timestamp of the last successful transfer.
struct CloudSyncStatus: Sendable, Equatable {
    let state: CloudSyncState
    /// Most recent successful export or import. Persisted across launches, so the
    /// row shows a real timestamp on a cold launch instead of staying blank until
    /// the first event of the session arrives. `nil` means "never synced".
    ///
    /// Displayable, but **never usable as a gate**: because it is restored from
    /// `UserDefaults`, it describes some past session of this install, not this
    /// one. Anything that needs "an import landed" wants
    /// `hasCompletedImportThisSession`.
    let lastSuccessfulSync: Date?
    /// `true` once an import has finished successfully **in this session** —
    /// i.e. mirroring has actually delivered whatever the account holds.
    ///
    /// The one signal in this app that separates "everything has arrived" from
    /// "nothing has happened yet". `state == .upToDate` cannot: it means no
    /// mirroring event is in flight, which is also true at cold launch before
    /// the first one opens. A consumer whose action is conditioned on the store
    /// being *empty* — `DefaultContentSeeder`'s stranded-library recovery — must
    /// gate on this rather than on the state or the timestamp.
    ///
    /// Never restored across launches: a flag that survived would say "arrived"
    /// about a session that is over, which is exactly the trap
    /// `lastSuccessfulSync` falls into.
    let hasCompletedImportThisSession: Bool

    init(
        state: CloudSyncState,
        lastSuccessfulSync: Date?,
        hasCompletedImportThisSession: Bool = false
    ) {
        self.state = state
        self.lastSuccessfulSync = lastSuccessfulSync
        self.hasCompletedImportThisSession = hasCompletedImportThisSession
    }

    static let off = CloudSyncStatus(state: .off, lastSuccessfulSync: nil)
}

/// Push-based source of the current iCloud sync status.
///
/// Deliberately has no `refresh()`/polling entry point: the implementation is
/// driven by CloudKit notifications, so consumers subscribe once and receive
/// every change.
@MainActor
protocol CloudSyncStatusProviding: AnyObject {
    /// Status as of now — safe to read before subscribing.
    var currentStatus: CloudSyncStatus { get }

    /// Emits the current status immediately, then every subsequent change.
    func statusUpdates() -> AsyncStream<CloudSyncStatus>
}
