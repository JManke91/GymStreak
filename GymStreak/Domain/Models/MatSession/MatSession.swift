//
//  MatSession.swift
//  GymStreak
//
//  A mat or sparring session the user logged after the fact — recorded as
//  training load (what, how long, how hard), never techniques or rounds.
//  See docs/fight-conditioning.md ("Mat sessions").
//

import Foundation
import SwiftData

/// The combat sport a mat session was spent on.
enum MatSport: String, CaseIterable, Identifiable, Sendable {
    case bjj, mma, muayThai, boxing, wrestling, other

    var id: String { rawValue }
}

/// How hard the session went. Three levels on purpose: the user logs this from
/// memory after training, and a finer scale would only be guessed.
enum MatIntensity: String, CaseIterable, Identifiable, Sendable {
    case drilling, moderate, hardSparring

    var id: String { rawValue }
}

/// One logged mat session.
///
/// **Its own `@Model`, not a `ConditioningRecord`.** The conditioning program's weekly
/// targets, today's suggestion, the watch offer and the post-workout add-on all read
/// `ConditioningRecord`, and sparring must count toward none of them — a separate
/// type keeps every one of those consumers unchanged instead of filtering in each.
/// Nor is it a `WorkoutSession`, for the reason `ConditioningRecord` is not.
///
/// Every stored property is optional or has a default (CloudKit private database);
/// enums are stored as raw strings, per `Models.swift`.
@Model
final class MatSession {
    /// Also the `HKMetadataKeyExternalUUID` on the Apple Health workout.
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date = Date()
    /// `MatSport` raw value.
    var sportRaw: String = ""
    /// `MatIntensity` raw value.
    var intensityRaw: String = ""
    var note: String = ""
    /// Set once the Apple Health workout was written; `nil` when Health sync is off
    /// or the write failed — the session is kept either way.
    var healthKitWorkoutId: UUID?

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date,
        sport: MatSport,
        intensity: MatIntensity,
        note: String = "",
        healthKitWorkoutId: UUID? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.sportRaw = sport.rawValue
        self.intensityRaw = intensity.rawValue
        self.note = note
        self.healthKitWorkoutId = healthKitWorkoutId
    }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    /// `.other` for a raw value a newer build wrote that this one does not know.
    var sport: MatSport { MatSport(rawValue: sportRaw) ?? .other }

    var intensity: MatIntensity? { MatIntensity(rawValue: intensityRaw) }
}
