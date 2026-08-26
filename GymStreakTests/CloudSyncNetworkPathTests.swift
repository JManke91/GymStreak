//
//  CloudSyncNetworkPathTests.swift
//  GymStreakTests
//
//  The offline decision behind the Settings iCloud row. Two device-measured
//  cases killed two earlier versions of this predicate (docs/settings-tab.md
//  §4.2), and both are pinned here — a `.satisfied` path made of nothing but a
//  VPN tunnel is offline, and a VPN over live Wi-Fi is not.
//

import Network
import Testing
@testable import GymStreak

@Suite
struct CloudSyncNetworkPathTests {

    /// Airplane mode with a VPN configured: the `utun` tunnel keeps the path
    /// `.satisfied` while nothing is reachable. Device log: `[other, other]`.
    @Test("A satisfied path of only virtual interfaces is offline")
    func vpnTunnelAloneIsOffline() {
        #expect(
            CloudKitSyncStatusMonitor.isOnline(
                status: .satisfied,
                interfaceTypes: [.other, .other]
            ) == false
        )
    }

    /// The regression that `prohibitedInterfaceTypes: [.other]` introduced: an
    /// always-on VPN over live Wi-Fi reported offline on a working device.
    /// Device log: `[other, other, wifi, cellular]`.
    @Test("A VPN over live Wi-Fi is online")
    func vpnOverWiFiIsOnline() {
        #expect(
            CloudKitSyncStatusMonitor.isOnline(
                status: .satisfied,
                interfaceTypes: [.other, .other, .wifi, .cellular]
            )
        )
    }

    @Test("Physical interfaces without a satisfied path are offline")
    func unsatisfiedIsOfflineWhateverIsListed() {
        #expect(
            CloudKitSyncStatusMonitor.isOnline(
                status: .unsatisfied,
                interfaceTypes: [.wifi, .cellular]
            ) == false
        )
    }

    @Test("Plain Wi-Fi and plain cellular are online")
    func physicalInterfacesAreOnline() {
        #expect(CloudKitSyncStatusMonitor.isOnline(status: .satisfied, interfaceTypes: [.wifi]))
        #expect(CloudKitSyncStatusMonitor.isOnline(status: .satisfied, interfaceTypes: [.cellular]))
    }

    @Test("A satisfied path listing no interfaces at all is offline")
    func noInterfacesIsOffline() {
        #expect(
            CloudKitSyncStatusMonitor.isOnline(status: .satisfied, interfaceTypes: []) == false
        )
    }

    /// The reason the predicate is an allowlist and not `!= .other`: loopback is
    /// not `.other`, and is not connectivity either.
    @Test("Loopback alone is offline")
    func loopbackAloneIsOffline() {
        #expect(
            CloudKitSyncStatusMonitor.isOnline(
                status: .satisfied,
                interfaceTypes: [.loopback, .other]
            ) == false
        )
    }

    @Test("Wired Ethernet counts, for a docked iPad")
    func wiredEthernetIsOnline() {
        #expect(
            CloudKitSyncStatusMonitor.isOnline(
                status: .satisfied,
                interfaceTypes: [.wiredEthernet]
            )
        )
    }
}
