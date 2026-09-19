//
//  ConditioningHistoryViewModel.swift
//  GymStreak
//
//  History's conditioning side: resolving a record for the detail screen and
//  deleting one (with its Apple Health counterpart when the user asks).
//  See docs/fight-conditioning.md and docs/delete-workout.md.
//

import Foundation
import Observation

/// Deliberately separate from `WorkoutViewModel` rather than another method on it.
///
/// `WorkoutViewModel` is the app-lifetime workout recorder; conditioning records share
/// none of its state and this screen needs three dependencies, not twenty. It reaches
/// History through the same seam every other non-workout mutation uses —
/// `.historySourceDataDidChange`, which `WorkoutViewModel` translates into the
/// `historyVersion` token the Trainings snapshot is keyed on.
@Observable
@MainActor
final class ConditioningHistoryViewModel {

    /// Non-blocking notice, mirroring the strength delete: the record is gone from
    /// GymStreak regardless, the user may still see the workout in Apple Health.
    var healthKitDeleteFailure: HealthKitDeleteFailure?

    @ObservationIgnored private let records: any ConditioningRecordRepository
    @ObservationIgnored private let healthKitManager: any HealthKitWorkoutServicing
    @ObservationIgnored private let historyStoreGate: HistoryStoreGate

    init(
        records: any ConditioningRecordRepository,
        healthKitManager: any HealthKitWorkoutServicing,
        historyStoreGate: HistoryStoreGate
    ) {
        self.records = records
        self.healthKitManager = healthKitManager
        self.historyStoreGate = historyStoreGate
    }

    /// Rows carry only a card id, so the `@Model` object is resolved here — the list
    /// itself never holds one (Performance rule 4).
    func record(id: UUID) -> ConditioningRecord? {
        records.find(id: id)
    }

    /// Deletes the record locally and, when asked, its Apple Health counterpart.
    ///
    /// SwiftData is the source of truth, so the local delete happens first and is never
    /// gated on, blocked by, or rolled back for HealthKit — only `healthKitDeleteFailure`
    /// records that Health did not follow.
    func delete(_ record: ConditioningRecord, alsoFromHealthKit: Bool) async {
        // Read before the delete: afterwards `record` is a tombstone and this property
        // can no longer be resolved.
        let healthKitWorkoutId = record.healthKitWorkoutId

        // The History model actor now fetches `ConditioningRecord` too, so a delete
        // landing mid-walk is the same uncatchable trap the gate exists to prevent
        // (docs/history-delete-race.md).
        await historyStoreGate.withExclusiveAccess {
            records.delete(record)
            do {
                try records.save()
            } catch {
                print("Error deleting conditioning record: \(error)")
            }
        }
        NotificationCenter.default.post(name: .historySourceDataDidChange, object: nil)

        guard alsoFromHealthKit, let healthKitWorkoutId else { return }
        do {
            // A `false` result means the workout was already absent from HealthKit —
            // the desired end state, not a failure.
            _ = try await healthKitManager.deleteWorkout(externalUUID: healthKitWorkoutId)
        } catch HealthKitError.healthAccessDenied {
            print("HealthKit conditioning delete refused: no Apple Health write access")
            healthKitDeleteFailure = .accessDenied
        } catch {
            print("HealthKit conditioning delete failed: \(error)")
            healthKitDeleteFailure = .failed
        }
    }

    func dismissHealthKitDeleteNotice() {
        healthKitDeleteFailure = nil
    }
}
