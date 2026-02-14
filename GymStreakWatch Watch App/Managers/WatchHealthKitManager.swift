import Foundation
import Combine
import HealthKit
import AppIntents

@MainActor
final class WatchHealthKitManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var heartRate: Double? = nil
    @Published var activeCalories: Double? = nil
    @Published var elapsedTime: TimeInterval = 0
    @Published var isWorkoutActive = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
//    @Published var currentHeartRate: Int? = nil
//    @Published var currentCalories: Int? = nil

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartDate: Date?

    private var heartRateQuery: HKAnchoredObjectQuery?
    private var caloriesQuery: HKAnchoredObjectQuery?

    // Optional routine name to attach as metadata when saving the workout
    private var currentRoutineName: String?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit: Not available on this device")
            return false
        }

        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            await updateAuthorizationStatus()
            return true
        } catch {
            print("HealthKit: Authorization failed - \(error.localizedDescription)")
            return false
        }
    }

    private func updateAuthorizationStatus() async {
        let status = healthStore.authorizationStatus(for: HKQuantityType.workoutType())
        authorizationStatus = status
    }

    // MARK: - Workout Session Management

    // Accept an optional routine name so we can save it as metadata later
    func startWorkout(routineName: String? = nil) async throws {
        // store the routine name for use when finishing the workout
        self.currentRoutineName = routineName

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
//            startHeartRateQuery()
//            startCaloriesBurnedQuery()
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()

            workoutSession?.delegate = self
            workoutBuilder?.delegate = self

            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutStartDate = Date()

            workoutSession?.startActivity(with: workoutStartDate!)
            try await workoutBuilder?.beginCollection(at: workoutStartDate!)

            isWorkoutActive = true
            startElapsedTimeTimer()

            print("HealthKit: Workout session started")
        } catch {
            print("HealthKit: Failed to start workout - \(error.localizedDescription)")
            throw error
        }
    }

    func pauseWorkout() {
        workoutSession?.pause()
    }

    func resumeWorkout() {
        workoutSession?.resume()
    }

    /// Ends the workout and saves it to HealthKit.
    /// Returns a tuple containing the saved HKWorkout and the external UUID used for deduplication.
    func endWorkout() async throws -> (workout: HKWorkout?, healthKitWorkoutId: UUID) {
        // Generate external UUID for deduplication and correlation with SwiftData
        let healthKitWorkoutId = UUID()

        guard let workoutSession = workoutSession,
              let workoutBuilder = workoutBuilder else {
            return (nil, healthKitWorkoutId)
        }

        workoutSession.end()

        do {
            try await workoutBuilder.endCollection(at: Date())

            // Add metadata. Use the routine name alone as the brand name so Health displays only the workout name.
            var metadata: [String: Any] = [:]

            // Add external UUID for deduplication across devices
            metadata[HKMetadataKeyExternalUUID] = healthKitWorkoutId.uuidString

            if let name = currentRoutineName, !name.isEmpty {
                metadata[HKMetadataKeyWorkoutBrandName] = name
                metadata["RoutineName"] = name
            } else {
                metadata[HKMetadataKeyWorkoutBrandName] = "GymStreak"
            }

            try? await workoutBuilder.addMetadata(metadata)

            let workout = try await workoutBuilder.finishWorkout()

            isWorkoutActive = false
            stopElapsedTimeTimer()
            resetMetrics()

            self.workoutSession = nil
            self.workoutBuilder = nil
            self.currentRoutineName = nil

            print("HealthKit: Workout ended and saved with ID: \(healthKitWorkoutId)")
            return (workout, healthKitWorkoutId)
        } catch {
            print("HealthKit: Failed to end workout - \(error.localizedDescription)")
            throw error
        }
    }

    func discardWorkout() {
        workoutSession?.end()
        workoutBuilder?.discardWorkout()
//        endHealthKitQueries()

        isWorkoutActive = false
        stopElapsedTimeTimer()
        resetMetrics()

        workoutSession = nil
        workoutBuilder = nil

        print("HealthKit: Workout discarded")
    }

    // MARK: - Timer Management

//    private func startCaloriesBurnedQuery(config: HKWorkoutConfiguration) {
//        workoutBuilder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
//        workoutBuilder?.statistics(for: .activeEnergyBurned)
//
//    }

//    private func startCaloriesBurnedQuery() {
//        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
//
//        caloriesQuery = HKAnchoredObjectQuery(
//            type: type,
//            predicate: nil,
//            anchor: nil,
//            limit: HKObjectQueryNoLimit
//        ) { _, samples, _, _, _ in
//            Task { @MainActor in
//                self.handleCalories(samples)
//            }
//        }
//
//        caloriesQuery?.updateHandler = { _, samples, _, _, _ in
//            Task { @MainActor in
//                self.handleCalories(samples)
//            }
//        }
//
//        healthStore.execute(caloriesQuery!)
//
//    }

//    private func handleCalories(_ samples: [HKSample]?) {
//        guard let quantitySample = samples?.first as? HKQuantitySample else { return }
//
//        let value = quantitySample.quantity.doubleValue(for: .kilocalorie())
//
//        DispatchQueue.main.async {
//            self.currentCalories = Int(value)
//        }
//    }

//    private func startHeartRateQuery() {
//        let type = HKObjectType.quantityType(forIdentifier: .heartRate)!
//
//        heartRateQuery = HKAnchoredObjectQuery(
//            type: type,
//            predicate: nil,
//            anchor: nil,
//            limit: HKObjectQueryNoLimit
//        ) { _, samples, _, _, _ in
////            self.handle(samples)
//            Task { @MainActor in
//                    self.handle(samples)
//                }
//        }
//
//        heartRateQuery?.updateHandler = { _, samples, _, _, _ in
////            self.handle(samples)
//            Task { @MainActor in
//                    self.handle(samples)
//                }
//        }
//
//        healthStore.execute(heartRateQuery!)
//    }

//    private func endHealthKitQueries() {
//        if let query = heartRateQuery {
//            healthStore.stop(query)
//            heartRateQuery = nil
//        }
//
////        if let heartRateQuery = heartRateQuery {
////            healthStore.stop(heartRateQuery)
////            self.heartRateQuery = nil
////        }
//    }

//    private func handle(_ samples: [HKSample]?) {
//        guard let quantitySample = samples?.first as? HKQuantitySample else { return }
//
//        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
//        let value = quantitySample.quantity.doubleValue(for: heartRateUnit)
//
//        DispatchQueue.main.async {
//            self.currentHeartRate = Int(value)   // Bind this to your SwiftUI or WKInterfaceLabel
//        }
//    }

    private var elapsedTimeTimer: Timer?

    private func startElapsedTimeTimer() {
        elapsedTimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startDate = self.workoutStartDate else { return }
                self.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = nil
    }

    private func resetMetrics() {
        heartRate = 0
        activeCalories = 0
        elapsedTime = 0
        workoutStartDate = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthKitManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.isWorkoutActive = true
            case .paused:
                self.isWorkoutActive = true // Still active, just paused
            case .ended:
                self.isWorkoutActive = false
            default:
                break
            }
            print("HealthKit: Workout state changed from \(fromState.rawValue) to \(toState.rawValue)")
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("HealthKit: Workout session failed - \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchHealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if let statistics = workoutBuilder.statistics(for: quantityType) {
                Task { @MainActor in
                    self.updateMetrics(for: quantityType, statistics: statistics)
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }

    @MainActor
    private func updateMetrics(for quantityType: HKQuantityType, statistics: HKStatistics) {
        switch quantityType {
        case HKQuantityType(.heartRate):
            if let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                heartRate = value
            }

        case HKQuantityType(.activeEnergyBurned):
            if let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                activeCalories = value
            }

        default:
            break
        }
    }
}
