//
//  WatchConditioningModels.swift
//
//  Wire formats between iPhone and watch for fight conditioning
//  (docs/fight-conditioning.md): the iOS → watch offer (ticket 06), the
//  watch → iOS finished session (ticket 07) and the watch → iOS mat session
//  (positioning ticket 05), which rides the same outbox, keys and ack. The offer rides as JSON `Data` under
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
    /// The heart-rate bands the watch's mat-session intensity suggestion reads.
    /// Independent of enrollment and of `validUntil`; absent without a usable
    /// heart-rate profile (or with the medication switch on), and from older iPhones.
    var matIntensityZones: WatchMatIntensityZones?
}

/// Where "moderate" and "hard" begin for a mat session, in bpm — the top of the
/// user's aerobic zone and the hard-effort threshold (`HeartRateZones` on iOS).
struct WatchMatIntensityZones: Codable, Equatable {
    var moderateFromBPM: Int
    var hardFromBPM: Int
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

/// Watch → iOS: one conditioning session finished on the watch (ticket 07). Carries
/// everything the iPhone's `ConditioningRecord` stores, so the iPhone copies it
/// rather than re-deriving it from a library that may have changed since.
struct WatchCompletedConditioningSession: Codable, Equatable, Identifiable {
    /// Also the `HKMetadataKeyExternalUUID` of the watch's Apple Health workout —
    /// the one key the iPhone dedupes on.
    var id: UUID
    var startTime: Date
    var endTime: Date
    var sessionType: String
    /// Localized on the watch; the iPhone uses it only as `titleSnapshot`.
    var title: String
    var energySystem: String
    var modality: String
    /// Effort of the work (or steady) phases.
    var effort: String
    var roundsCompleted: Int
    var roundsPlanned: Int
    var setsPlanned: Int
    var workInterval: TimeInterval
    var restInterval: TimeInterval
    var endedEarly: Bool
    /// Whether the watch saved the Apple Health workout — the iPhone never writes one.
    var isSavedToHealth: Bool
}

/// Watch → iOS: one mat session recorded on the watch (positioning ticket 05).
/// Carries what the iPhone's `MatSession` stores; enums as raw strings.
struct WatchCompletedMatSession: Codable, Equatable, Identifiable {
    /// Also the `HKMetadataKeyExternalUUID` of the watch's Apple Health workout.
    var id: UUID
    var startTime: Date
    var endTime: Date
    /// `MatSport` raw value.
    var sport: String
    /// `MatIntensity` raw value — what the user confirmed on the watch.
    var intensity: String
    var isSavedToHealth: Bool
}

enum WatchConditioningWire {
    /// `transferUserInfo` keys for a finished session and the iPhone's acknowledgment.
    /// Distinct from the strength workout keys, so neither path mistakes the other's payload.
    nonisolated static let completedSessionKey = "conditioningSession"
    /// Also carried by a mat session, so the watch's outstanding-transfer check and
    /// the ack (`ackKey`) cover both kinds unchanged.
    nonisolated static let completedSessionIdKey = "conditioningSessionId"
    nonisolated static let completedMatSessionKey = "matSession"
    nonisolated static let ackKey = "conditioningAck"

    /// Sorted keys, so an unchanged offer produces identical bytes and is not resent.
    static func encode(_ program: WatchConditioningProgram) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(program)
    }

    static func decode(_ data: Data) -> WatchConditioningProgram? {
        try? JSONDecoder().decode(WatchConditioningProgram.self, from: data)
    }

    static func userInfo(for session: WatchCompletedConditioningSession) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(session) else { return nil }
        return [completedSessionKey: data, completedSessionIdKey: session.id.uuidString]
    }

    /// `nil` when the payload is not a finished conditioning session.
    static func completedSession(from payload: [String: Any]) -> WatchCompletedConditioningSession? {
        guard let data = payload[completedSessionKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCompletedConditioningSession.self, from: data)
    }

    static func userInfo(for session: WatchCompletedMatSession) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(session) else { return nil }
        return [completedMatSessionKey: data, completedSessionIdKey: session.id.uuidString]
    }

    /// `nil` when the payload is not a finished mat session.
    static func completedMatSession(from payload: [String: Any]) -> WatchCompletedMatSession? {
        guard let data = payload[completedMatSessionKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCompletedMatSession.self, from: data)
    }
}
