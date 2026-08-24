import Foundation
import HealthKit

/// Writes and removes the iPhone's Apple Health workouts.
///
/// The phone records nothing live: a workout is written **once, after the fact**
/// with `HKWorkoutBuilder`. See `docs/healthkit-ios-workout-save.md` for why the
/// live `HKWorkoutSession` path was removed.
@MainActor
class HealthKitWorkoutManager: ObservableObject, HealthKitWorkoutServicing {

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var authorizationError: String?
    @Published var lastSyncError: String?
    @Published var lastSyncedWorkout: HKWorkout?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()

    // MARK: - HealthKit Availability

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// Request authorization to read and write workout data
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        // Types we want to read
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        // Types we want to write
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

        // Check if we have write permission for workouts
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        isAuthorized = status == .sharingAuthorized

        if !isAuthorized {
            authorizationError = "Workout write permission not granted"
        }
    }

    /// Check current authorization status without requesting
    func checkAuthorizationStatus() {
        guard isHealthKitAvailable else {
            isAuthorized = false
            return
        }

        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        isAuthorized = status == .sharingAuthorized
    }

    // MARK: - Save Workout

    /// Save a completed workout after the fact.
    ///
    /// Order matters: the energy sample and the metadata — brand name plus
    /// `HKMetadataKeyExternalUUID` — are added **before** `endCollection`, which
    /// deactivates the builder. Adding them afterwards is what made the removed
    /// live-session path write metadata-less workouts.
    ///
    /// Returns a tuple containing the saved HKWorkout and the external UUID used for deduplication.
    func saveWorkoutDirectly(
        startDate: Date,
        endDate: Date,
        totalEnergyBurned: Double? = nil,
        metadata: [String: Any]? = nil
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID) {
        // Generate external UUID for deduplication and correlation with SwiftData
        let healthKitWorkoutId = UUID()

        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        // Names the awaited call in the failure log. HealthKit reports the same
        // `errorAuthorizationDenied` for every write, so without this a denial
        // cannot be attributed to a step — which is what made "Not authorized"
        // unactionable when only the energy sample was refused.
        var step = "beginCollection"

        do {
            try await builder.beginCollection(at: startDate)

            // Energy is a nice-to-have. Sharing authorization is *per type*:
            // Workouts can be granted while Active Energy is not, and HealthKit
            // then refuses this sample with `errorAuthorizationDenied`. The
            // workout record itself carries the routine name and the external
            // UUID everything downstream correlates on, so a refused sample must
            // never sink it.
            if let energy = totalEnergyBurned, energy > 0, canShareActiveEnergy {
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: energy)
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: energyQuantity,
                    start: startDate,
                    end: endDate
                )
                do {
                    try await builder.addSamples([energySample])
                } catch {
                    print("HealthKit: active-energy sample skipped, workout still saved — \(error)")
                }
            }

            // Merge provided metadata with external UUID
            var finalMetadata = metadata ?? [:]
            finalMetadata[HKMetadataKeyExternalUUID] = healthKitWorkoutId.uuidString

            step = "addMetadata"
            try await builder.addMetadata(finalMetadata)

            step = "endCollection"
            try await builder.endCollection(at: endDate)

            step = "finishWorkout"
            let workout = try await builder.finishWorkout()

            self.lastSyncedWorkout = workout
            self.lastSyncError = nil

            if workout != nil {
                print("HealthKit workout saved directly with ID: \(healthKitWorkoutId)")
            }

            return (workout, healthKitWorkoutId)

        } catch {
            print("Failed to save workout directly at \(step): \(error)")
            self.lastSyncError = error.localizedDescription
            throw HealthKitError.saveFailed(error.localizedDescription)
        }
    }

    /// Whether Apple Health currently accepts active-energy writes from this app.
    /// Separate from `isAuthorized`, which only reports the workout type.
    private var canShareActiveEnergy: Bool {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return false
        }
        return healthStore.authorizationStatus(for: energyType) == .sharingAuthorized
    }

    // MARK: - Deletion

    /// Delete the HKWorkout carrying `externalUUID` in its external-UUID metadata.
    ///
    /// The workout is located by our own metadata rather than a persisted
    /// `HKWorkout.uuid`, so no additional SwiftData field is needed. Scoping the
    /// query to our own source is unnecessary — HealthKit enforces the ownership
    /// rule on delete regardless of what the query matched.
    ///
    /// Deleting the workout also removes the quantity samples its builder
    /// associated with it (active energy, distance, heart rate). Activity Ring
    /// exercise minutes are system-awarded and cannot be deleted by any app.
    @discardableResult
    func deleteWorkout(externalUUID: UUID) async throws -> Bool {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalUUID.uuidString]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )

        do {
            let matches = try await descriptor.result(for: healthStore)
            // Nothing to delete: already gone, or the read was silently denied.
            // Either way the desired end state holds.
            guard let workout = matches.first else { return false }
            try await healthStore.delete(workout)
            print("HealthKit workout deleted for external ID: \(externalUUID)")
            return true
        } catch {
            print("Failed to delete HealthKit workout: \(error)")
            throw HealthKitError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Utility

    /// Estimate calories burned for strength training
    /// Based on average of 3-6 calories per minute for moderate strength training
    func estimateCaloriesBurned(durationInSeconds: TimeInterval) -> Double {
        let minutes = durationInSeconds / 60.0
        let caloriesPerMinute = 4.5 // Average for moderate strength training
        return minutes * caloriesPerMinute
    }
}

// MARK: - Error Types

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case saveFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization not granted"
        case .saveFailed(let message):
            return "Failed to save workout: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete workout: \(message)"
        }
    }
}
