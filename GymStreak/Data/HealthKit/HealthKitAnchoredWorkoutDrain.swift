//
//  HealthKitAnchoredWorkoutDrain.swift
//  GymStreak
//
//  Incremental HealthKit workout discovery (ticket 09 of in-workout routine
//  editing). Replaces the old repeated moving 30-day full-store poll with a
//  serialized `HKAnchoredObjectQueryDescriptor` over `HKObjectType.workoutType()`
//  paired with a persisted anchor and a FIXED lower-bound predicate. The
//  descriptor's async `result(for:)` returns the added samples, the deleted
//  objects, and the new anchor in one drain-all-pages call.
//
//  This type is a pure query wrapper: it performs NO persistence. The caller
//  (`WorkoutRecoveryCoordinator`) applies the returned changes to the ledger
//  and only then commits the new anchor, so a crash between drain and persist
//  replays the same changes idempotently instead of skipping them.
//
//  Added samples are filtered to GymStreak-authored workouts that carry our
//  `HKMetadataKeyExternalUUID`; anything else cannot be correlated safely and
//  is ignored. Deleted objects expose only the HealthKit object UUID (their
//  external-UUID metadata is NOT preserved by the system), so we pass every
//  deleted UUID through — the ledger maps the ones it knows back to a
//  candidate and ignores the rest.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitAnchoredWorkoutDrain {
    /// All GymStreak-authored workouts (iOS app or watch app) share this bundle
    /// prefix; the watch suffix is `.watchkitapp`.
    static let gymStreakBundlePrefix = "com.shotat24fps.GymStreak"

    struct Changes {
        let discovered: [DiscoveredWorkoutFacts]
        let deletedObjectUUIDs: [UUID]
        let newAnchor: HKQueryAnchor
    }

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// Drains all pages for the fixed predicate from `anchor` (nil bootstraps a
    /// full first-run discovery). Throws on query failure so the caller leaves
    /// the anchor unchanged and retries on the next trigger.
    func drain(anchor: HKQueryAnchor?, lowerBound: Date) async throws -> Changes {
        let datePredicate = HKQuery.predicateForSamples(withStart: lowerBound, end: nil, options: [])
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(datePredicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: healthStore)

        let discovered = result.addedSamples.compactMap(Self.facts(from:))
        let deleted = result.deletedObjects.map(\.uuid)
        return Changes(
            discovered: discovered,
            deletedObjectUUIDs: deleted,
            newAnchor: result.newAnchor
        )
    }

    /// Maps a GymStreak-authored HKWorkout that carries our external UUID into
    /// ledger discovery facts. Returns nil for third-party workouts or ones
    /// missing the external-UUID metadata (which predate the dedup scheme and
    /// can't be correlated).
    static func facts(from workout: HKWorkout) -> DiscoveredWorkoutFacts? {
        let bundleId = workout.sourceRevision.source.bundleIdentifier
        guard bundleId.hasPrefix(gymStreakBundlePrefix) else { return nil }

        guard
            let metadata = workout.metadata,
            let uuidString = metadata[HKMetadataKeyExternalUUID] as? String,
            let externalUUID = UUID(uuidString: uuidString)
        else { return nil }

        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let routineName = (metadata["RoutineName"] as? String)
            ?? (metadata[HKMetadataKeyWorkoutBrandName] as? String)
            ?? "Workout"
        let routineId = (metadata["RoutineId"] as? String).flatMap(UUID.init)

        return DiscoveredWorkoutFacts(
            externalUUID: externalUUID,
            healthKitObjectUUID: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            activeEnergyKilocalories: energy,
            routineName: routineName,
            routineId: routineId,
            fromWatch: bundleId.hasSuffix(".watchkitapp")
        )
    }
}
