//
//  WatchConditioningModels.swift
//
//  iOS → watch wire format for the conditioning offer (ticket 06,
//  docs/fight-conditioning.md). Rides as JSON `Data` under
//  `WatchConditioningProgram.contextKey` in the SAME application context as the
//  routines — `updateApplicationContext` replaces the whole dictionary, so a
//  context of its own would clobber them (see the weight unit, which does the same).
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Models/` — keep them in sync. Strings for the
//  enums on purpose: a watch that does not know a newer value skips that one
//  session instead of failing to decode the whole offer.
//

import Foundation

struct WatchConditioningProgram: Codable, Equatable {
    static let contextKey = "conditioningProgram"

    /// Start of the day the iPhone computed the offer; "today" is marked only on it.
    var day: Date
    /// End of the program week. Past it the watch shows no conditioning entry.
    var validUntil: Date
    /// Empty when the user is not enrolled, paused, not started or done.
    var sessions: [WatchConditioningSession]
}

struct WatchConditioningSession: Codable, Equatable, Identifiable {
    /// `ConditioningSessionDefinition.ID.rawValue` — one target per session a week.
    var sessionType: String
    var energySystem: String
    /// `ConditioningModality.rawValue`s this session can be done on, the default first.
    var modalities: [String]
    /// Minutes, rounds or sets — whatever the session's volume counts.
    var volume: Int
    var isSuggestedToday: Bool
    /// Already expanded by the iPhone; the watch only runs them.
    var phases: [ConditioningPhase]
    /// For the conversational phases only; absent for RPE-only users.
    var heartRateZone: WatchHeartRateZone?

    var id: String { sessionType }
}

struct WatchHeartRateZone: Codable, Equatable {
    var lowerBPM: Int
    var upperBPM: Int
}

enum WatchConditioningWire {
    /// Sorted keys, so an unchanged offer produces identical bytes and is not resent.
    static func encode(_ program: WatchConditioningProgram) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(program)
    }

    static func decode(_ data: Data) -> WatchConditioningProgram? {
        try? JSONDecoder().decode(WatchConditioningProgram.self, from: data)
    }
}
