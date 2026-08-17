//
//  FounderCelebrationStore.swift
//  GymStreak
//
//  The durable half of the Founder celebration: that it has been seen.
//  See docs/pro-subscription.md §5h.
//

import Foundation

/// Remembers that the Founder thank-you screen was shown, so it is shown once
/// and never again.
///
/// Plain `UserDefaults.standard`, matching `PaywallPresenter`'s once-ever record
/// and `ProactivePaywallTriggerStore` rather than the allowance store's App
/// Group + iCloud KVS pair:
///
/// - **Not the App Group suite** — neither the widget nor the watch shows this
///   screen, and per `monetization-strategy.md` §4.1 the watch never learns
///   about entitlements at all.
/// - **Not mirrored to iCloud** — this is device-local presentation history. The
///   worst outcome of not mirroring it is that a reinstall thanks the user a
///   second time, which is benign; mirroring it would instead risk a Founder who
///   never sees the screen because another device recorded it while they were
///   not looking.
///
/// The flag is cached in memory, seeded at init, because it is read on every
/// launch and every foreground and `UserDefaults` is not observable.
@MainActor
final class FounderCelebrationStore: FounderCelebrationTracking {

    private(set) var hasCelebrated: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCelebrated = defaults.bool(forKey: Self.celebratedKey)
    }

    func recordCelebrated() {
        guard !hasCelebrated else { return }
        hasCelebrated = true
        defaults.set(true, forKey: Self.celebratedKey)
    }

    #if DEBUG
    func resetCelebration() {
        hasCelebrated = false
        defaults.removeObject(forKey: Self.celebratedKey)
    }
    #endif

    private static let celebratedKey = "pro.founderCelebrationShown"
}
