import Foundation
import HealthKit

/// Manages HealthKit workout sessions for syncing workouts with Apple Health
@MainActor
class HealthKitWorkoutManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var authorizationError: String?
    @Published var isWorkoutActive = false
    @Published var lastSyncError: String?
    @Published var lastSyncedWorkout: HKWorkout?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

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

    // MARK: - Workout Session Management

    /// Start a new workout session for strength training
    func startWorkoutSession() async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        guard !isWorkoutActive else {
            throw HealthKitError.workoutAlreadyActive
        }

        // Configure the workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            // Create the workout session
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self

            // Get the associated workout builder
            let builder = session.associatedWorkoutBuilder()
            builder.delegate = self

            // Set up the data source for automatic data collection
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            // Start the session and begin data collection
            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            // Store references
            self.workoutSession = session
            self.workoutBuilder = builder
            self.isWorkoutActive = true
            self.lastSyncError = nil

            print("HealthKit workout session started")

        } catch {
            print("Failed to start HealthKit workout: \(error)")
            throw HealthKitError.sessionStartFailed(error.localizedDescription)
        }
    }

    /// End the current workout session and save to HealthKit.
    /// Returns a tuple containing the saved HKWorkout and the external UUID used for deduplication.
    func endWorkoutSession(
        totalEnergyBurned: Double? = nil,
        metadata: [String: Any]? = nil
    ) async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID) {
        // Generate external UUID for deduplication and correlation with SwiftData
        let healthKitWorkoutId = UUID()

        guard let session = workoutSession, let builder = workoutBuilder else {
            throw HealthKitError.noActiveWorkout
        }

        let endDate = Date()

        do {
            // End the session
            session.end()

            // End data collection
            try await builder.endCollection(at: endDate)

            // Add energy burned if provided
            if let energy = totalEnergyBurned, energy > 0 {
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: energy)
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: energyQuantity,
                    start: session.startDate ?? endDate,
                    end: endDate
                )
                try await builder.addSamples([energySample])
            }

            // Merge provided metadata with external UUID
            var finalMetadata = metadata ?? [:]
            finalMetadata[HKMetadataKeyExternalUUID] = healthKitWorkoutId.uuidString

            try await builder.addMetadata(finalMetadata)

            // Finish and save the workout
            let workout = try await builder.finishWorkout()

            // Clean up
            self.workoutSession = nil
            self.workoutBuilder = nil
            self.isWorkoutActive = false
            self.lastSyncedWorkout = workout
            self.lastSyncError = nil

            if let workout = workout {
                print("HealthKit workout saved successfully with ID: \(healthKitWorkoutId)")
            }

            return (workout, healthKitWorkoutId)

        } catch {
            print("Failed to end HealthKit workout: \(error)")
            self.lastSyncError = error.localizedDescription

            // Clean up even on failure
            self.workoutSession = nil
            self.workoutBuilder = nil
            self.isWorkoutActive = false

            throw HealthKitError.saveFailed(error.localizedDescription)
        }
    }

    /// Cancel the current workout session without saving to HealthKit
    func cancelWorkoutSession() {
        guard let session = workoutSession, let builder = workoutBuilder else {
            // No active session, just clean up
            workoutSession = nil
            workoutBuilder = nil
            isWorkoutActive = false
            lastSyncError = nil
            return
        }

        // End the session first
        session.end()

        // Discard the workout builder to prevent saving to HealthKit
        // This is the key - we call discardWorkout() instead of finishWorkout()
        Task {
            do {
                try await builder.endCollection(at: Date())
                builder.discardWorkout()
                print("HealthKit workout discarded successfully")
            } catch {
                print("Error discarding HealthKit workout: \(error)")
            }
        }

        // Clean up references
        workoutSession = nil
        workoutBuilder = nil
        isWorkoutActive = false
        lastSyncError = nil

        print("HealthKit workout session cancelled - workout NOT saved to Health")
    }

    /// Pause the current workout session
    func pauseWorkoutSession() {
        workoutSession?.pause()
    }

    /// Resume the current workout session
    func resumeWorkoutSession() {
        workoutSession?.resume()
    }

    // MARK: - Fallback: Save Workout Without Session

    /// Save a completed workout directly without using a session (fallback).
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

        do {
            try await builder.beginCollection(at: startDate)

            // Add energy burned if provided
            if let energy = totalEnergyBurned, energy > 0 {
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: energy)
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: energyQuantity,
                    start: startDate,
                    end: endDate
                )
                try await builder.addSamples([energySample])
            }

            // Merge provided metadata with external UUID
            var finalMetadata = metadata ?? [:]
            finalMetadata[HKMetadataKeyExternalUUID] = healthKitWorkoutId.uuidString

            try await builder.addMetadata(finalMetadata)

            try await builder.endCollection(at: endDate)

            let workout = try await builder.finishWorkout()

            self.lastSyncedWorkout = workout
            self.lastSyncError = nil

            if let workout = workout {
                print("HealthKit workout saved directly with ID: \(healthKitWorkoutId)")
            }

            return (workout, healthKitWorkoutId)

        } catch {
            print("Failed to save workout directly: \(error)")
            self.lastSyncError = error.localizedDescription
            throw HealthKitError.saveFailed(error.localizedDescription)
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

// MARK: - HKWorkoutSessionDelegate

extension HealthKitWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            print("Workout session state changed: \(fromState.rawValue) -> \(toState.rawValue)")

            switch toState {
            case .running:
                isWorkoutActive = true
            case .ended, .stopped:
                isWorkoutActive = false
            case .paused:
                // Keep isWorkoutActive true when paused
                break
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            print("Workout session failed: \(error)")
            lastSyncError = error.localizedDescription
            isWorkoutActive = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HealthKitWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // Handle collected data if needed (e.g., heart rate updates)
        // For strength training, we primarily care about duration and energy
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}

// MARK: - Error Types

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case workoutAlreadyActive
    case noActiveWorkout
    case sessionStartFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization not granted"
        case .workoutAlreadyActive:
            return "A workout session is already active"
        case .noActiveWorkout:
            return "No active workout session to end"
        case .sessionStartFailed(let message):
            return "Failed to start workout session: \(message)"
        case .saveFailed(let message):
            return "Failed to save workout: \(message)"
        }
    }
}
