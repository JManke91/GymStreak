//
//  ConditioningRecord.swift
//  GymStreak
//
//  A finished conditioning session, recorded in GymStreak's own history.
//  See docs/fight-conditioning.md.
//

import Foundation
import SwiftData

/// One completed conditioning session.
///
/// **Not a `WorkoutSession` with zero exercises.** History cards, Fortschritt,
/// the muscle map and PR computation all walk `workoutExercises → sets` and
/// would each have to special-case an empty session; a separate type keeps that
/// code untouched and lets this row carry what conditioning actually has
/// (rounds, work/rest intervals, effort) instead of empty strength fields.
///
/// Denormalized like `WorkoutSession`: it copies everything it displays rather
/// than pointing at a `ConditioningSessionDefinition`, so retuning or removing a
/// session in `ConditioningLibrary` never rewrites what the user did.
///
/// Every stored property is optional or has a default — the CloudKit private
/// database requires it, and the app has no migration plan (additive lightweight
/// migration only). Enums are stored as raw strings, per `Models.swift`.
@Model
final class ConditioningRecord {
    /// Also the `HKMetadataKeyExternalUUID` stamped on the Apple Health workout,
    /// so the record and its Health counterpart correlate without a second id.
    /// It is assigned before the Health write, so it exists even when the write
    /// is skipped or fails.
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date = Date()

    /// `ConditioningSessionDefinition.ID` raw value.
    var sessionTypeRaw: String = ""
    /// The title as it read when the session was performed.
    ///
    /// Only used when `sessionTypeRaw` no longer names a session in the library:
    /// while it does, the title is re-localized from the definition, so History
    /// follows the user's language instead of freezing the language they trained in.
    var titleSnapshot: String = ""
    /// `ConditioningEnergySystem` raw value.
    var energySystemRaw: String = ""
    /// `ConditioningModality` raw value.
    var modalityRaw: String = ""
    /// `ConditioningEffort` raw value of the work phases — this is also what
    /// records whether the 85–90 % beginner variant was used (`.subMaximal`).
    var effortRaw: String = ""

    /// Work intervals actually finished. 0 for steady state, which has none.
    var roundsCompleted: Int = 0
    /// Work intervals the plan contained. 0 for steady state.
    var roundsPlanned: Int = 0
    /// Sets the plan was organized into; 0 when the session is not set-based.
    var setsPlanned: Int = 0
    /// Length of one work interval; 0 for steady state.
    var workInterval: TimeInterval = 0
    /// Rest between work intervals; 0 for steady state.
    var restInterval: TimeInterval = 0

    /// The user ended before the timeline ran out.
    var endedEarly: Bool = false
    /// Set once the Apple Health workout was written. `nil` when Health sync is
    /// off, Health is unavailable, or the write failed — the record is kept
    /// either way, so History never depends on Apple Health.
    var healthKitWorkoutId: UUID?

    init(
        id: UUID,
        startTime: Date,
        endTime: Date,
        sessionTypeRaw: String,
        titleSnapshot: String,
        energySystemRaw: String,
        modalityRaw: String,
        effortRaw: String,
        roundsCompleted: Int,
        roundsPlanned: Int,
        setsPlanned: Int,
        workInterval: TimeInterval,
        restInterval: TimeInterval,
        endedEarly: Bool,
        healthKitWorkoutId: UUID? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.sessionTypeRaw = sessionTypeRaw
        self.titleSnapshot = titleSnapshot
        self.energySystemRaw = energySystemRaw
        self.modalityRaw = modalityRaw
        self.effortRaw = effortRaw
        self.roundsCompleted = roundsCompleted
        self.roundsPlanned = roundsPlanned
        self.setsPlanned = setsPlanned
        self.workInterval = workInterval
        self.restInterval = restInterval
        self.endedEarly = endedEarly
        self.healthKitWorkoutId = healthKitWorkoutId
    }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    /// `nil` once the library no longer defines the session this was run from —
    /// callers fall back to `titleSnapshot`.
    var sessionType: ConditioningSessionDefinition.ID? {
        ConditioningSessionDefinition.ID(rawValue: sessionTypeRaw)
    }

    var energySystem: ConditioningEnergySystem? {
        ConditioningEnergySystem(rawValue: energySystemRaw)
    }

    var modality: ConditioningModality? {
        ConditioningModality(rawValue: modalityRaw)
    }

    var effort: ConditioningEffort? {
        ConditioningEffort(rawValue: effortRaw)
    }

    /// Steady-state sessions have no rounds; the duration is the whole story.
    var isSteadyState: Bool { roundsPlanned == 0 }
}

extension ConditioningRecord {

    /// Builds the record for a finished run.
    ///
    /// Everything comes from the plan and the timeline the runner actually
    /// executed, so a later edit to `ConditioningLibrary` cannot change it.
    /// `title` is passed in rather than derived: localized copy lives in
    /// Presentation, and `Domain/` must not reach into it.
    ///
    /// - Parameters:
    ///   - id: also the Apple Health external UUID. Assigned by the caller
    ///     before the Health write so the record exists even if that write never happens.
    ///   - elapsed: session time at the moment it ended, pauses excluded.
    static func make(
        id: UUID,
        plan: ConditioningSessionPlan,
        timeline: ConditioningTimeline,
        title: String,
        startDate: Date,
        endDate: Date,
        elapsed: TimeInterval,
        endedEarly: Bool
    ) -> ConditioningRecord {
        let definition = plan.definition
        let setsPlanned: Int = switch definition.volume {
        case .sets: max(1, plan.options.volume)
        case .rounds, .minutes: 0
        }
        // The effort the *work* phases carried — which is how the beginner
        // variant is recorded, since it only changes that effort.
        let workEffort = timeline.phases.first { $0.kind.isEffort }?.effort ?? definition.effort

        return ConditioningRecord(
            id: id,
            startTime: startDate,
            endTime: endDate,
            sessionTypeRaw: definition.id.rawValue,
            titleSnapshot: title,
            energySystemRaw: definition.energySystem.rawValue,
            modalityRaw: plan.modality.rawValue,
            effortRaw: workEffort.rawValue,
            roundsCompleted: timeline.completedWorkIntervals(at: elapsed),
            roundsPlanned: timeline.workIntervalCount,
            setsPlanned: setsPlanned,
            workInterval: definition.work ?? 0,
            restInterval: definition.work == nil ? 0 : definition.rest,
            endedEarly: endedEarly
        )
    }
}
