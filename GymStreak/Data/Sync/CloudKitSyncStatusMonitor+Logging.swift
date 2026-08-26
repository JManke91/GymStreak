//
//  CloudKitSyncStatusMonitor+Logging.swift
//  GymStreak
//
//  How a sync failure gets recorded. Split out of CloudKitSyncStatusMonitor so
//  that file stays under the 300-line limit, as SyncEventSummary was before it.
//  See docs/settings-tab.md §4.2.
//

import CloudKit
import Foundation
import Network
import OSLog

extension CloudKitSyncStatusMonitor {

    /// One `LogSubsystem.sync` filter shows the whole sync story for a launch —
    /// this category and `RoutineSave`.
    ///
    /// **The two levels are not equally retrievable.** The `.error` entries
    /// (`logStoreFallback`, `log(_ event:)`) are persisted to the on-disk store,
    /// so they reach a TestFlight tester's sysdiagnose after the fact — that is
    /// the point of them. The `.debug` entries (`logNetworkPath`,
    /// `logStateVector`) are not captured unless logging is explicitly enabled,
    /// so they are readable only from a live
    /// `log stream --level debug` against a paired device. That is the right
    /// trade for a per-path-change vector nobody should be persisting, but do
    /// not expect a remote crash report to contain them.
    ///
    /// `private` in an extension is file-scoped, and all four call sites are in
    /// this file; the `log…` functions stay internal for the monitor to call.
    ///
    /// `nonisolated` because the monitor is `@MainActor`, which would otherwise
    /// isolate this property too and put it out of reach of `logNetworkPath` —
    /// `NWPathMonitor` calls that one on its own queue. Safe as the checked
    /// escape hatch: `Logger` is `Sendable` and a `static let` is immutable.
    nonisolated private static let logger = Logger(
        subsystem: LogSubsystem.sync,
        category: "Mirroring"
    )

    /// Records that the app is running without CloudKit because the container
    /// could not be built. `GymStreakApp` cannot log this itself — the store is
    /// constructed before any dependency exists — so the reason is carried here.
    static func logStoreFallback(_ description: String) {
        logger.error(
            "CloudKit store unavailable, running local-only: \(description, privacy: .public)"
        )
    }

    /// Records every failed transfer, not only the ones that change the state: a
    /// schema rejection used to be indistinguishable from a queued upload, which
    /// is how the plan-mirroring bug survived a month (docs/workout-planning.md).
    static func log(_ event: SyncEventSummary) {
        if event.endDate != nil, !event.succeeded {
            logger.error(
                """
                mirroring \(event.type.rawValue, privacy: .public) failed \
                (persistent: \(event.isPersistentFailure, privacy: .public)): \
                \(event.errorDescription ?? "unknown", privacy: .public)
                """
            )
        }
        #if DEBUG
        // Whether SwiftData's container emits these events at all can only be
        // confirmed on a device signed into iCloud — this log is how that check
        // is made (see docs/settings-tab.md §"Verification record").
        print("☁️ [CloudKitSyncStatusMonitor] event type=\(event.type.rawValue) ended=\(event.endDate != nil) succeeded=\(event.succeeded) error=\(event.errorDescription ?? "none")")
        #endif
    }

    /// The offline-detection counterpart of `logStateVector`: which interfaces
    /// `NWPathMonitor` sees is what separates "no network" from a stalled event.
    ///
    /// `nonisolated` because `NWPathMonitor` calls its handler on its own queue —
    /// this only reads the `NWPath` it was handed and touches no state.
    nonisolated static func logNetworkPath(_ path: NWPath, isSatisfied: Bool) {
        let interfaces = path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",")
        // An OSLog entry as well as a `print`, at `.debug` because nothing is
        // wrong here — this is diagnosis. The VPN `.other` bug was invisible on
        // any build Xcode was not attached to, which is most of them.
        logger.debug(
            "path satisfied=\(isSatisfied, privacy: .public) interfaces=\(interfaces, privacy: .public)"
        )
        #if DEBUG
        print("☁️ [CloudKitSyncStatusMonitor] path status=\(path.status) satisfied=\(isSatisfied) expensive=\(path.isExpensive) constrained=\(path.isConstrained) interfaces=[\(interfaces)]")
        #endif
    }

    /// Logs the whole input vector, not just the resulting state: the airplane-mode
    /// regression (row returns to "Aktuell" while offline) can only come from
    /// `hasNetwork` or `hasQueuedChanges` being wrong, and this is what tells the
    /// two apart on a device. See docs/settings-tab.md §7.
    static func logStateVector(
        state: CloudSyncState,
        hasNetwork: Bool,
        inFlight: Int,
        queued: Bool,
        persistentFailure: Bool,
        account: CKAccountStatus?
    ) {
        let accountDescription = account.map(String.init(describing:)) ?? "unqueried"
        logger.debug(
            "state=\(String(describing: state), privacy: .public) hasNetwork=\(hasNetwork, privacy: .public) inFlight=\(inFlight, privacy: .public) queued=\(queued, privacy: .public) persistentFailure=\(persistentFailure, privacy: .public) account=\(accountDescription, privacy: .public)"
        )
        #if DEBUG
        print("☁️ [CloudKitSyncStatusMonitor] state=\(state) hasNetwork=\(hasNetwork) inFlight=\(inFlight) queued=\(queued) persistentFailure=\(persistentFailure) account=\(accountDescription)")
        #endif
    }
}
