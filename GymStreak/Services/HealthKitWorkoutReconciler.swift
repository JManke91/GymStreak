import Foundation
import HealthKit

/// Detects HKWorkout records that GymStreak (iOS or watch) has saved to HealthKit
/// but for which no matching `WorkoutSession` exists in SwiftData.
///
/// This is the safety-net layer of the watch→iOS sync architecture (see
/// `docs/watch-sync.md`). The four upstream layers (watch persistent retry,
/// dual-path send, iOS receive buffer, idempotent ingest) prevent silent loss
/// in the common cases. The reconciler covers residual edge cases:
/// - Watch app uninstalled & reinstalled, clearing its retry queue
/// - HKWorkout saved before the new sync code was deployed
/// - WC pairing disrupted between saves
///
/// HKWorkout cannot fully reconstruct a `WorkoutSession` (it lacks per-set rep
/// and weight detail), so this service only *detects* orphans and surfaces
/// them. The user is prompted to re-open GymStreak on their watch, where the
/// retry queue will redeliver the workout if it's still buffered.
@MainActor
final class HealthKitWorkoutReconciler {
    /// An HKWorkout that GymStreak saved but has no matching SwiftData record.
    struct OrphanedWorkout: Identifiable, Hashable {
        let id: UUID  // healthKitWorkoutId from HKMetadataKeyExternalUUID
        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let activeEnergyBurnedKilocalories: Double?
        let sourceBundleIdentifier: String
        /// Routine name read from HK metadata (RoutineName / WorkoutBrandName).
        let routineName: String
        /// Routine id read from HK metadata, if the workout was recorded by a build
        /// that embeds it. Lets recovery match the exact routine template.
        let routineId: UUID?

        var fromWatch: Bool {
            sourceBundleIdentifier.hasSuffix(".watchkitapp")
        }
    }

    private let healthStore = HKHealthStore()

    /// All HKWorkouts authored by GymStreak (iOS app or watch app) share this
    /// bundle prefix. Suffix is `.watchkitapp` for watch-saved workouts.
    private let gymStreakBundlePrefix = "com.shotat24fps.GymStreak"

    /// Default lookback window. We don't surface very old orphans — if a user
    /// has had a missing workout for months they've likely moved on.
    nonisolated static let defaultLookbackDays = 30

    /// Queries HealthKit for GymStreak-authored workouts in the lookback window
    /// and returns those whose external UUID does not appear in `knownIds`.
    ///
    /// - Parameters:
    ///   - knownIds: The `healthKitWorkoutId` values already present in the
    ///     iOS SwiftData store. The caller (WorkoutViewModel) computes this
    ///     from its existing `workoutHistory` cache.
    ///   - lookbackDays: How far back to look. Defaults to 30 days.
    /// - Returns: An array of orphaned workouts sorted newest-first.
    func findOrphanedWorkouts(
        knownIds: Set<UUID>,
        lookbackDays: Int = HealthKitWorkoutReconciler.defaultLookbackDays
    ) async -> [OrphanedWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else {
            return []
        }

        // NOTE: we intentionally do NOT gate on `authorizationStatus(for:)`. That API
        // reports *sharing (write)* status only — it says nothing about read access,
        // and HealthKit always returns samples an app wrote itself regardless of read
        // authorization. Gating on `.sharingAuthorized` here previously suppressed the
        // query (and any recovery) for users who hadn't granted write access on iOS.

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: endDate) ?? endDate
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        let workouts: [HKWorkout]
        do {
            workouts = try await fetchWorkouts(predicate: predicate)
        } catch {
            print("HealthKitWorkoutReconciler: query failed - \(error.localizedDescription)")
            return []
        }

        return workouts.compactMap { workout -> OrphanedWorkout? in
            // Only consider workouts authored by GymStreak.
            let bundleId = workout.sourceRevision.source.bundleIdentifier
            guard bundleId.hasPrefix(gymStreakBundlePrefix) else { return nil }

            // Only consider workouts that have our external UUID metadata.
            // Anything we save via WatchHealthKitManager / HealthKitWorkoutManager
            // sets this; workouts without it predate the dedup scheme and we
            // can't correlate them safely.
            guard
                let metadata = workout.metadata,
                let uuidString = metadata[HKMetadataKeyExternalUUID] as? String,
                let externalId = UUID(uuidString: uuidString)
            else {
                return nil
            }

            // If we already have a WorkoutSession for this id, it's not an orphan.
            guard !knownIds.contains(externalId) else { return nil }

            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())

            let routineName = (metadata["RoutineName"] as? String)
                ?? (metadata[HKMetadataKeyWorkoutBrandName] as? String)
                ?? "Workout"
            let routineId = (metadata["RoutineId"] as? String).flatMap(UUID.init)

            return OrphanedWorkout(
                id: externalId,
                startDate: workout.startDate,
                endDate: workout.endDate,
                duration: workout.duration,
                activeEnergyBurnedKilocalories: energy,
                sourceBundleIdentifier: bundleId,
                routineName: routineName,
                routineId: routineId
            )
        }
        .sorted { $0.startDate > $1.startDate }
    }

    private func fetchWorkouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }
}
