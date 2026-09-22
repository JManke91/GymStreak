//
//  ConditioningWatchPublishing.swift
//  GymStreak
//
//  Publishes the conditioning offer to the watch (ticket 06,
//  docs/fight-conditioning.md). Implemented by the WatchConnectivity adapter,
//  which merges it into the routine application context.
//

import Foundation

@MainActor
protocol ConditioningWatchPublishing: AnyObject {
    /// Idempotent: an unchanged offer sends nothing.
    func publishConditioningOffer(_ offer: ConditioningWatchOffer)
}
