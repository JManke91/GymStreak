//
//  ProactivePaywallTriggerStore.swift
//  GymStreak
//
//  The durable half of §8's two proactive placements: which triggers have
//  already become true. See docs/pro-subscription.md §5g.
//

import Foundation

/// Remembers that a §8 A/B trigger fired, so a moment that could not be shown
/// (Rule 3, a cover in the way) is *deferred* rather than lost.
///
/// Plain `UserDefaults.standard`, matching `PaywallPresenter`'s once-ever record
/// rather than the allowance store's App Group + iCloud KVS pair:
///
/// - **Not the App Group suite** — neither the widget nor the watch can act on a
///   paywall trigger, and per §4.1 the watch never learns about entitlements.
/// - **Not mirrored to iCloud** — this is device-local presentation history that
///   only pairs with the once-ever record it sits beside, and mirroring one half
///   of the pair would let a reinstalled device believe a placement is still
///   pending after it was already shown elsewhere.
///
/// The flags are cached in memory, seeded at init: `isArmed(_:)` is asked on
/// every workout completion and every routine creation, and `UserDefaults` is
/// not observable, so a view rendering from the answer would otherwise only pick
/// up a change on the next launch — the same reason `PaywallPresenter` keeps its
/// fired set in memory.
@MainActor
final class ProactivePaywallTriggerStore: ProactivePaywallTracking {

    private var armed: Set<ProactivePaywallTrigger>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.armed = Set(
            ProactivePaywallTrigger.allCases.filter { defaults.bool(forKey: $0.storageKey) }
        )
    }

    func isArmed(_ trigger: ProactivePaywallTrigger) -> Bool {
        armed.contains(trigger)
    }

    func arm(_ trigger: ProactivePaywallTrigger) {
        guard armed.insert(trigger).inserted else { return }
        defaults.set(true, forKey: trigger.storageKey)
    }
}

#if DEBUG
extension ProactivePaywallTriggerStore: ProactivePaywallTrackingDebugging {

    func resetTriggers() {
        armed.removeAll()
        for trigger in ProactivePaywallTrigger.allCases {
            defaults.removeObject(forKey: trigger.storageKey)
        }
    }
}
#endif
