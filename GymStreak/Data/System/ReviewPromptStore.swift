//
//  ReviewPromptStore.swift
//  GymStreak
//
//  The durable half of the automatic rating prompt: that it has been asked for.
//  See docs/rating-prompt.md.
//

import Foundation

/// Remembers that the app has asked the system for a review, so it asks once
/// and never again.
///
/// Plain `UserDefaults.standard`, matching `FounderCelebrationStore` and
/// `ProactivePaywallTriggerStore` rather than the allowance store's App Group +
/// iCloud KVS pair:
///
/// - **Not the App Group suite** — neither the widget nor the watch can show a
///   review alert. `SKStoreReviewController`/`RequestReviewAction` is an iOS and
///   macOS API with no watchOS counterpart, so the watch has nothing to read
///   this for.
/// - **Not mirrored to iCloud** — Apple's own throttle is **per device**, so the
///   fact this record guards is a per-device fact. Mirroring it would make the
///   app's bookkeeping disagree with the system's: a second device would believe
///   it had already asked when, as far as StoreKit is concerned, it never has,
///   and the ask would be silently lost on that device forever. The worst
///   outcome of *not* mirroring is that a new device asks once — which is
///   exactly what Apple's throttle is designed to absorb.
///
/// The flag is cached in memory, seeded at init, because it is read after every
/// completed workout and `UserDefaults` is not observable.
@MainActor
final class ReviewPromptStore: ReviewPromptTracking {

    private(set) var hasRequestedReview: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasRequestedReview = defaults.bool(forKey: Self.requestedKey)
    }

    func recordReviewRequested() {
        guard !hasRequestedReview else { return }
        hasRequestedReview = true
        defaults.set(true, forKey: Self.requestedKey)
    }

    private static let requestedKey = "review.prompt.requested"
}
