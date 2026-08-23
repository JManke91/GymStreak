//
//  ProRestoreOutcome.swift
//  GymStreak
//
//  What a user-initiated restore is allowed to tell the user.
//  See docs/pro-subscription.md §5i.
//

import Foundation

/// The result of a restore the user asked for.
///
/// **Three cases, not two, and the third is the reason this type exists.**
/// "Found nothing" and "could not ask" are the same silence to the entitlement
/// layer — both leave the state untouched — but they are opposite messages to a
/// person: one says *you never bought this*, the other says *try again in a
/// moment*. Telling someone who paid that they never did is the worst outcome a
/// restore can produce, so the distinction is carried out of the Data layer
/// rather than reconstructed from `isPro` at the call site.
///
/// It is the same `.none`-vs-error distinction `PurchasedProEntitlement`
/// already draws (§3d), surfaced one layer up because here it is user-facing.
enum ProRestoreOutcome: Equatable, Sendable {

    /// The restore ran and the account holds Pro. The gates are already open.
    case restored

    /// The restore ran and the account holds nothing. A fact about the account.
    case nothingFound

    /// The restore could not run — offline, or the backend refused. **Nothing
    /// was revoked**: whatever entitlement was held before still stands.
    case failed
}
