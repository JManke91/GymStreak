//
//  WatchWirePayload.swift
//  GymStreak
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Models/` — keep them in sync.
//

import Foundation

/// Carries a WatchConnectivity plist payload across the hop from a `nonisolated`
/// `WCSessionDelegate` callback to the main actor.
///
/// WCSession delivers payloads as `[String: Any]`, and `Any` is not `Sendable`, so
/// the dictionary cannot cross an isolation boundary on its own.
///
/// **Why `@unchecked Sendable` is sound here** — the invariant is verifiable in this
/// repository rather than a claim about Apple's implementation: the box is a `let`,
/// the dictionary is only ever read, and each box is created in exactly one delegate
/// callback and consumed by exactly one `Task`. That hand-off establishes a
/// happens-before edge, so even lazily-bridged `NSDictionary` storage is never
/// touched concurrently.
///
/// **Rules for use:** consume each box exactly once, and never store `payload` for
/// later cross-isolation reads — both would break the hand-off argument above.
///
/// Deliberately a transport box rather than a re-typed value: re-encoding each plist
/// value into a closed `Sendable` enum would risk silently dropping or widening a
/// value the sync protocol depends on (the routine authority encodes `UInt64`
/// generations as decimal strings precisely because plists are lossy here). Boxing
/// keeps the received payload byte-identical and leaves every existing parser
/// signature untouched. Same pattern as `HealthKitWorkoutObserver.CompletionBox`.
///
/// `nonisolated` because it is constructed inside `nonisolated` delegate callbacks:
/// the watch target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise
/// make even the initializer main-actor-isolated.
nonisolated struct WatchWirePayload: @unchecked Sendable {
    let payload: [String: Any]

    init(_ payload: [String: Any]) {
        self.payload = payload
    }
}
