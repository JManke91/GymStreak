//
//  ConditioningWatchOffer.swift
//  GymStreak
//
//  What the iPhone offers the watch for conditioning: the enrolled user's
//  open sessions of the current program week, today's suggestion first, with
//  the personal heart-rate range already computed (ticket 06,
//  docs/fight-conditioning.md). The watch has no program logic of its own.
//

import Foundation

struct ConditioningWatchOffer: Equatable, Sendable {

    struct Session: Equatable, Sendable {
        let plan: ConditioningSessionPlan
        /// The coach's suggestion for today, rather than another open target of the week.
        let isSuggestedToday: Bool
        /// The range for the session's conversational phases; `nil` for every other
        /// effort and for RPE-only users (medication switch on or no profile).
        let heartRateTarget: HeartRateTarget?
    }

    let sessions: [Session]
    /// The start of the day the offer was computed — the watch shows "today" only on
    /// that day. A day, not an instant, so an unchanged offer encodes identically all day.
    let day: Date
    /// The end of the current program week: after it the offer is stale and the
    /// watch shows no conditioning entry until the iPhone publishes a new one.
    let validUntil: Date

    /// Not enrolled, paused, not started or completed: the watch shows nothing.
    static func none(on day: Date) -> ConditioningWatchOffer {
        ConditioningWatchOffer(sessions: [], day: day, validUntil: day)
    }
}
