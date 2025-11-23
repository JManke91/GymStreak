import Foundation
import Combine
import HealthKit

@MainActor
final class WatchHealthKitManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var isWorkoutActive = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartDate: Date?

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

    func startWorkout() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
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

    func endWorkout() async throws -> HKWorkout? {
        guard let workoutSession = workoutSession,
              let workoutBuilder = workoutBuilder else {
            return nil
        }

        workoutSession.end()

        do {
            try await workoutBuilder.endCollection(at: Date())
            let workout = try await workoutBuilder.finishWorkout()

            isWorkoutActive = false
            stopElapsedTimeTimer()
            resetMetrics()

            self.workoutSession = nil
            self.workoutBuilder = nil

            print("HealthKit: Workout ended and saved")
            return workout
        } catch {
            print("HealthKit: Failed to end workout - \(error.localizedDescription)")
            throw error
        }
    }

    func discardWorkout() {
        workoutSession?.end()
        workoutBuilder?.discardWorkout()

        isWorkoutActive = false
        stopElapsedTimeTimer()
        resetMetrics()

        workoutSession = nil
        workoutBuilder = nil

        print("HealthKit: Workout discarded")
    }

    // MARK: - Timer Management

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
