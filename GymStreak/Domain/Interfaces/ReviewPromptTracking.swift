//
//  ReviewPromptTracking.swift
//  GymStreak
//
//  Whether this device has already been asked to rate the app.
//  See docs/rating-prompt.md.
//

import Foundation

/// The durable "we have already asked for a rating on this device" record.
///
/// Its own protocol rather than a flag on anything existing, for the reason
/// `FounderCelebrationTracking` is its own: this is device-local presentation
/// history, and it is the only thing standing between the user and a second
/// unprompted alert.
///
/// **One-way and never re-armed.** Apple's own throttle already caps the prompt
/// at three per 365 days and never re-asks a user who rated on this device, and
/// it reports nothing back about whether the alert appeared. So the app cannot
/// know whether an ask succeeded and must not retry on the assumption that it
/// did not — the record is written when the ask *goes out*, not when a rating
/// arrives, because there is no signal that a rating arrived.
///
/// `@MainActor` like the rest of the presentation-history surface, and it
/// imports nothing beyond Foundation on purpose: no `UserDefaults` key and no
/// StoreKit type may appear in this signature.
@MainActor
protocol ReviewPromptTracking: AnyObject {

    /// Whether the automatic rating prompt has already been asked for on this
    /// device. Cheap by contract — it is asked after every completed workout, so
    /// a conformer answers from memory rather than from I/O.
    var hasRequestedReview: Bool { get }

    /// Records that the review request was handed to the system. Idempotent,
    /// one-way: nothing ever un-asks.
    func recordReviewRequested()
}
