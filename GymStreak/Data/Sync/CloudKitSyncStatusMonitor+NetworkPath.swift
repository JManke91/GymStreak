//
//  CloudKitSyncStatusMonitor+NetworkPath.swift
//  GymStreak
//
//  The "is this device actually online" judgment. Split out of
//  CloudKitSyncStatusMonitor so that file stays under the 300-line limit, as
//  SyncEventSummary and +Logging were before it. See docs/settings-tab.md §4.2 —
//  two device-measured dead ends produced this one expression.
//

import Network

extension CloudKitSyncStatusMonitor {

    /// Whether the device can actually reach something, rather than merely
    /// having a route. Two device-measured dead ends produced this predicate —
    /// `.satisfied` alone, and `prohibitedInterfaceTypes: [.other]` — and
    /// docs/settings-tab.md §4.2 records why each failed and in which direction.
    ///
    /// Split from its `NWPath` so it can be tested: `NWPath` has no public
    /// initializer, its inputs do (`CloudSyncNetworkPathTests`).
    nonisolated static func isOnline(_ path: NWPath) -> Bool {
        isOnline(
            status: path.status,
            interfaceTypes: path.availableInterfaces.map(\.type)
        )
    }

    /// An allowlist rather than `!= .other`: it excludes `.loopback` without a
    /// special case, and a virtual interface type Apple adds later is excluded
    /// by default instead of silently counting as real connectivity.
    nonisolated static func isOnline(
        status: NWPath.Status,
        interfaceTypes: [NWInterface.InterfaceType]
    ) -> Bool {
        status == .satisfied
            && interfaceTypes.contains { $0 == .wifi || $0 == .cellular || $0 == .wiredEthernet }
    }
}
