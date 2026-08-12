//
//  CloudSyncStatusProviding.swift
//  GymStreak
//
//  Domain-facing view of the iCloud sync state shown in Settings.
//  Implemented in Data by `CloudKitSyncStatusMonitor` — see docs/settings-tab.md.
//

import Foundation

/// The four states the Settings iCloud row distinguishes.
enum CloudSyncState: Sendable, Equatable {
    /// Everything the app knows about has been exported and imported successfully.
    case upToDate
    /// A transfer is in flight right now.
    case syncing
    /// Changes are queued but the last transfer failed for a recoverable reason
    /// (typically no network).
    case waiting
    /// iCloud is not available for this app: signed out, restricted, or the
    /// CloudKit store failed to build and the app fell back to a local-only store.
    case off
}

/// Sync state plus the timestamp of the last successful transfer.
struct CloudSyncStatus: Sendable, Equatable {
    let state: CloudSyncState
    /// Most recent successful export or import. Persisted across launches, so the
    /// row shows a real timestamp on a cold launch instead of staying blank until
    /// the first event of the session arrives. `nil` means "never synced".
    let lastSuccessfulSync: Date?

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
