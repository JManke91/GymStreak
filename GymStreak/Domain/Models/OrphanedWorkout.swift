//
//  OrphanedWorkout.swift
//  GymStreak
//
//  A HealthKit-authored GymStreak workout that has no matching rich history and
//  that the recovery reconciler has cleared to OFFER for explicit,
//  user-confirmed, history-only reconstruction (ticket 09 of in-workout routine
//  editing). Derived from a durable `WorkoutRecoveryLedgerEntry`; it is the
//  presentation-facing candidate the History banner renders.
//
//  Pure Domain value type so both the Data coordinator that produces it and the
//  Presentation banner that displays it depend only on Domain.
//

import Foundation

struct OrphanedWorkout: Identifiable, Hashable, Sendable {
    /// The HealthKit external UUID (`HKMetadataKeyExternalUUID`) — the stable
    /// identity shared with any rich payload that later replaces the recovery.
    let id: UUID
    let startDate: Date
    let endDate: Date
    let activeEnergyBurnedKilocalories: Double?
    /// Routine name read from HealthKit metadata (falls back to "Workout").
    let routineName: String
    /// Routine id from HealthKit metadata, when the recording build embedded it
    /// — lets recovery match the exact routine template.
    let routineId: UUID?
    let fromWatch: Bool

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    init(
        id: UUID,
        startDate: Date,
        endDate: Date,
        activeEnergyBurnedKilocalories: Double?,
        routineName: String,
        routineId: UUID?,
        fromWatch: Bool
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activeEnergyBurnedKilocalories = activeEnergyBurnedKilocalories
        self.routineName = routineName
        self.routineId = routineId
        self.fromWatch = fromWatch
    }

    init(ledgerEntry entry: WorkoutRecoveryLedgerEntry) {
        self.init(
            id: entry.externalUUID,
            startDate: entry.startDate,
            endDate: entry.endDate,
            activeEnergyBurnedKilocalories: entry.activeEnergyKilocalories,
            routineName: entry.routineName,
            routineId: entry.routineId,
            fromWatch: entry.fromWatch
        )
    }
}
