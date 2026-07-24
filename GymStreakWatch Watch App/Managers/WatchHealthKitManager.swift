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

    // Optional routine name/id to attach as metadata when saving the workout
    private var currentRoutineName: String?
    private var currentRoutineId: UUID?

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

    // Accept an optional routine name/id so we can save them as metadata later
    func startWorkout(routineName: String? = nil, routineId: UUID? = nil) async throws {
        // store the routine name/id for use when finishing the workout
        self.currentRoutineName = routineName
        self.currentRoutineId = routineId

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

    /// Everything a finalization operates on, captured on its FIRST call and
    /// keyed by the workout's external UUID. A retried (or slow, still-running)
    /// finalization always acts on this bound pair — never on the manager's
    /// live `workoutSession`/`workoutBuilder`, which `startWorkout` may already
    /// have replaced with a NEWER workout's session. Without the binding, a
    /// retry after a metadata/finish failure would end or finish the new
    /// workout instead. `hasEndedCollection` lives here so a retry never
    /// re-ends the collection or produces a second end time.
    private struct BoundFinalization {
        let externalId: UUID
        let session: HKWorkoutSession
        let builder: HKLiveWorkoutBuilder
        let routineId: UUID?
        let routineName: String?
        var hasEndedCollection = false
    }

    private var boundFinalization: BoundFinalization?

    /// Finalization step 1 (see WatchWorkoutFinalizer): ends live collection
    /// and stamps the REQUIRED external-UUID metadata. GymStreak correlates
    /// the SwiftData session, the WatchConnectivity payload, and this
    /// HKWorkout by that UUID (HealthKit permits duplicates and does not
    /// dedupe on it), so a metadata failure must throw — it is never
    /// swallowed into a transportable state. Idempotent across retries:
    /// `addMetadata` replaces existing keys on the same builder.
    func endCollectionAndAddMetadata(externalId healthKitWorkoutId: UUID) async throws {
        if let bound = boundFinalization, bound.externalId != healthKitWorkoutId {
            // A different workout's finalization was abandoned in this process
            // (its queue entry is recovered by the summary-dismissal retry or
            // the launch-time promotion). Release its HealthKit objects so
            // they can never be confused with the live workout's.
            bound.builder.discardWorkout()
            boundFinalization = nil
        }
        if boundFinalization == nil {
            guard let workoutSession = workoutSession,
                  let workoutBuilder = workoutBuilder else {
                // No live HealthKit workout (start failed) — nothing to finalize.
                return
            }
            boundFinalization = BoundFinalization(
                externalId: healthKitWorkoutId,
                session: workoutSession,
                builder: workoutBuilder,
                routineId: currentRoutineId,
                routineName: currentRoutineName
            )
        }
        guard let bound = boundFinalization else { return }

        if !bound.hasEndedCollection {
            bound.session.end()
            try await bound.builder.endCollection(at: Date())
            boundFinalization?.hasEndedCollection = true
        }

        // Use the routine name alone as the brand name so Health displays only the workout name.
        var metadata: [String: Any] = [:]
        metadata[HKMetadataKeyExternalUUID] = healthKitWorkoutId.uuidString

        // Embed the routine id so iOS can match this workout to the exact routine
        // template if it ever has to reconstruct the session from HealthKit alone
        // (i.e. the rich WatchConnectivity payload was lost).
        if let routineId = bound.routineId {
            metadata["RoutineId"] = routineId.uuidString
        }

        if let name = bound.routineName, !name.isEmpty {
            metadata[HKMetadataKeyWorkoutBrandName] = name
            metadata["RoutineName"] = name
        } else {
            metadata[HKMetadataKeyWorkoutBrandName] = "GymStreak"
        }

        try await bound.builder.addMetadata(metadata)
        print("HealthKit: collection ended, external UUID stamped: \(healthKitWorkoutId)")
    }

    /// Finalization step 2: finishes the bound workout/builder. Failure keeps
    /// the binding alive so a retry finishes the identical workout. No
    /// fallback to the live `workoutBuilder`: without a binding there is
    /// nothing safe to finish (the live builder may belong to a newer
    /// workout), matching the no-live-workout early return in step 1.
    func finishWorkout() async throws {
        guard let builder = boundFinalization?.builder else {
            return
        }

        do {
            _ = try await builder.finishWorkout()
        } catch {
            print("HealthKit: Failed to finish workout - \(error.localizedDescription)")
            throw error
        }

        // Tear down live-workout state only while it still belongs to the
        // workout just finished — startWorkout may already own a newer session.
        if workoutBuilder === builder || workoutBuilder == nil {
            isWorkoutActive = false
            stopElapsedTimeTimer()
            resetMetrics()

            workoutSession = nil
            workoutBuilder = nil
            currentRoutineName = nil
            currentRoutineId = nil
        }
        boundFinalization = nil

        print("HealthKit: Workout finished and saved")
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

    // MARK: - Active Session Recovery (ticket 08)

    /// True when this manager currently owns a live session/builder. Used to
    /// classify recovery outcomes and gate idempotent adoption.
    var hasLiveWorkoutSession: Bool { workoutSession != nil }

    /// Attempts to reconnect an active `HKWorkoutSession` a previous process
    /// left behind (crash/relaunch mid-workout). Returns nil when nothing is
    /// active to recover — Apple restores ONLY a still-active session, never one
    /// already ended or finished (see docs/watch-workout-recovery.md). Available
    /// since watchOS 5; safe to call whether or not a recovery callback fired.
    func recoverActiveSession() async -> HKWorkoutSession? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        do {
            return try await healthStore.recoverActiveWorkoutSession()
        } catch {
            print("HealthKit: recoverActiveWorkoutSession failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Reconnects a recovered session and its builder to this manager. Delegates
    /// are reattached BEFORE the live data source: a freshly-assigned
    /// `HKLiveWorkoutDataSource` can immediately surface already-buffered samples
    /// through `HKLiveWorkoutBuilderDelegate`, so attaching the delegate first
    /// avoids dropping that first batch. Idempotent — a second adoption while a
    /// session is already owned is a no-op (guards against duplicate recovery
    /// callbacks, whose repeat behavior Apple does not document).
    @discardableResult
    func adoptRecoveredSession(_ session: HKWorkoutSession, startDate: Date) -> Bool {
        guard workoutSession == nil else { return workoutSession === session }
        let builder = session.associatedWorkoutBuilder()

        session.delegate = self
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: session.workoutConfiguration
        )

        workoutSession = session
        workoutBuilder = builder
        workoutStartDate = startDate
        isWorkoutActive = true
        startElapsedTimeTimer()
        print("HealthKit: recovered active workout session adopted")
        return true
    }

    /// Restores the routine name/id used for finalization metadata on a resumed
    /// workout. The recovered session/builder carries no app metadata until
    /// `endCollectionAndAddMetadata` stamps it, so a resuming caller supplies it
    /// from the app checkpoint / frozen payload.
    func restoreRoutineMetadata(routineName: String?, routineId: UUID?) {
        currentRoutineName = routineName
        currentRoutineId = routineId
    }

    /// Whether an `HKWorkout` carrying `externalUUID` is already saved. Used to
    /// reconcile a durable finalization phase against Apple Health when no active
    /// session is recoverable — the workout may have finished-and-saved just
    /// before the crash. Reuses the app's cross-device external-UUID key.
    func savedWorkoutExists(externalUUID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                allowedValues: [externalUUID.uuidString]
            )
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples?.isEmpty == false))
            }
            healthStore.execute(query)
        }
    }

    /// Finishes a recovered session that has no app checkpoint (missing/corrupt):
    /// preserve the workout in Apple Health WITHOUT fabricating GymStreak routine
    /// or template membership. iOS orphan reconciliation later surfaces it under
    /// the History "Add to history" banner. No-op if no live session is owned.
    func finishOrphanRecoveredSession() async {
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        do {
            session.end()
            try await builder.endCollection(at: Date())
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "GymStreak"])
            _ = try await builder.finishWorkout()
            print("HealthKit: orphan recovered session finished and saved (no app checkpoint)")
        } catch {
            print("HealthKit: failed to finish orphan recovered session — \(error.localizedDescription)")
        }
        isWorkoutActive = false
        stopElapsedTimeTimer()
        resetMetrics()
        workoutSession = nil
        workoutBuilder = nil
        currentRoutineName = nil
        currentRoutineId = nil
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
            Task { @MainActor [weak self] in
                guard let self, let startDate = self.workoutStartDate else { return }
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

// MARK: - WorkoutFinalizationHealthKit

/// The finalizer sequences endCollectionAndAddMetadata → finishWorkout
/// against the durable outgoing queue's phases (see WatchWorkoutFinalizer).
extension WatchHealthKitManager: WorkoutFinalizationHealthKit {}

// MARK: - HKWorkoutSessionDelegate

extension WatchHealthKitManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.isWorkoutActive = true
                // Session is now actually running — safe point to (re)donate the
                // Action Button next action. Also fires on resume, which simply
                // re-registers the complete-set intent.
                await AppStateProvider.shared.workoutViewModel?.donateActionButtonIntent()
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
        // Coalesce all collected types into ONE main-actor hop: heart rate and
        // energy often arrive in the same callback, and publishing them from
        // separate tasks lands as separate SwiftUI transactions in the same
        // frame ("tried to update multiple times per frame" warnings).
        let collected = collectedTypes.compactMap { type -> (HKQuantityType, HKStatistics)? in
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { return nil }
            return (quantityType, statistics)
        }
        guard !collected.isEmpty else { return }

        Task { @MainActor in
            for (quantityType, statistics) in collected {
                self.updateMetrics(for: quantityType, statistics: statistics)
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
