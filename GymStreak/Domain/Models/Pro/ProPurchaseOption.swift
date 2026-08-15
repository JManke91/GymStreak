//
//  ProPurchaseOption.swift
//  GymStreak
//
//  What the app can offer to buy, and how a purchase attempt ended — described
//  without naming a store. See docs/pro-subscription.md §3b.
//

import Foundation

/// One buyable Pro product, reduced to what a purchase surface needs to show.
///
/// A projection, not a store object: the RevenueCat `Package`/`StoreProduct` it
/// came from stays inside `Data/Purchases/`, and `id` is what the purchase call
/// names it by. Prices arrive already localized by the store, so nothing above
/// the Data layer ever formats a currency.
struct ProPurchaseOption: Identifiable, Equatable, Sendable {

    /// The store's identifier for this product — the token a purchase names.
    let id: String

    /// Store-provided display name (e.g. "Yearly").
    let displayName: String

    /// Store-provided, already-localized price string (e.g. "€29.99").
    let price: String
}

/// How a purchase attempt ended.
enum ProPurchaseResult: Equatable, Sendable {

    /// The store accepted the purchase. The entitlement follows from the
    /// customer record, not from this value.
    case purchased

    /// The user dismissed the purchase sheet. **Not an error**: it must never
    /// reach an alert, which is why it is a result case rather than a thrown
    /// error the caller has to remember to special-case.
    case cancelled

    /// The store refused or failed. Carries an already-localized message.
    case failed(String)
}
