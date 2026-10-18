//
//  WatchConditioningWorkoutManager.swift
//  GymStreakWatch Watch App
//
//  The Apple Health side of a watch conditioning session (ticket 06,
//  docs/fight-conditioning.md): its OWN `HKWorkoutSession` + live builder with
//  the modality's activity type — never the strength session, because
//  multi-activity sessions are restricted to swim-bike-run. The active session
//  also grants the background runtime the runner's haptics need.
//
//  A mat session (positioning ticket 05) is recorded by a second instance of
//  this same manager through `MatSessionWorkoutRecording`: only the activity
//  type and the session-kind metadata differ.
//
//  Kept apart from `WatchHealthKitManager` on purpose: that manager's
//  finalization is bound to the durable strength queue, which conditioning
//  does not use.
//

import Foundation
import HealthKit

/// What `WatchConditioningRunViewModel` needs from HealthKit, so it can be tested.
@MainActor
protocol ConditioningWorkoutRecording: AnyObject {
    /// Live heart rate in bpm, as the builder collects it.
    var onHeartRate: ((Int) -> Void)? { get set }
    /// The session failed or was ended from outside — typically another workout
    /// started, which force-ends this one.
    var onSessionFailed: (() -> Void)? { get set }
    func start(modality: String, at date: Date) async throws
    func pause()
    func resume()
    /// Ends collection at `end`, stamps the metadata and saves the workout.
    func finish(at end: Date, externalUUID: UUID, title: String) async throws
    /// Ends the session and saves nothing.
    func discard()
}

/// What `WatchMatSessionViewModel` needs from HealthKit: the same live session, with
/// the sport's configuration and the mat session kind.
@MainActor
protocol MatSessionWorkoutRecording: AnyObject {
    var onHeartRate: ((Int) -> Void)? { get set }
    var onSessionFailed: (() -> Void)? { get set }
    func start(sport: String, at date: Date) async throws
    func pause()
    func resume()
    func finishMatSession(at end: Date, externalUUID: UUID, title: String) async throws
    func discard()
}

@MainActor
final class WatchConditioningWorkoutManager: NSObject, ConditioningWorkoutRecording, MatSessionWorkoutRecording {

    /// Metadata the iPhone's recovery drain reads to leave conditioning out of the
    /// strength recovery banner (`HealthKitAnchoredWorkoutDrain`). Same key and value.
    static let sessionKindKey = "GymStreakSessionKind"
    static let sessionKindValue = "conditioning"
    /// The iPhone's `HealthKitWorkoutManager.matSessionKind`.
    static let matSessionKindValue = "mat"

    var onHeartRate: ((Int) -> Void)?
    var onSessionFailed: (() -> Void)?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// The same run → `.running` outdoor, bike → `.cycling` indoor, rower → `.rowing`
    /// indoor, sled/ropes/med ball → HIIT indoor mapping as the iPhone. Swim never
    /// reaches the watch (see `WatchConditioningMapper` on iOS).
    static func configuration(for modality: String) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        switch modality {
        case "run":
            configuration.activityType = .running
            configuration.locationType = .outdoor
        case "assaultBike":
            configuration.activityType = .cycling
            configuration.locationType = .indoor
        case "rower":
            configuration.activityType = .rowing
            configuration.locationType = .indoor
        default:
            configuration.activityType = .highIntensityIntervalTraining
            configuration.locationType = .indoor
        }
        return configuration
    }

    /// The iPhone's mat mapping (`HealthKitWorkoutManager.configuration(for: MatSport)`):
    /// BJJ, MMA and Muay Thai → martial arts, boxing, wrestling, else other; indoor.
    static func configuration(forSport sport: String) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = switch sport {
        case "bjj", "mma", "muayThai": .martialArts
        case "boxing": .boxing
        case "wrestling": .wrestling
        default: .other
        }
        configuration.locationType = .indoor
        return configuration
    }

    func start(modality: String, at date: Date) async throws {
        try await start(Self.configuration(for: modality), at: date)
    }

    func start(sport: String, at date: Date) async throws {
        try await start(Self.configuration(forSport: sport), at: date)
    }

    func finish(at end: Date, externalUUID: UUID, title: String) async throws {
        try await finish(at: end, externalUUID: externalUUID, title: title, kind: Self.sessionKindValue)
    }

    func finishMatSession(at end: Date, externalUUID: UUID, title: String) async throws {
        try await finish(at: end, externalUUID: externalUUID, title: title, kind: Self.matSessionKindValue)
    }

    private func start(_ configuration: HKWorkoutConfiguration, at date: Date) async throws {
        // Prompts only for undecided types; the strength flow has usually asked already.
        try await healthStore.requestAuthorization(
            toShare: [HKQuantityType.workoutType()],
            read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        )
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        attach(session: session, builder: builder)
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
    }

    func pause() { session?.pause() }

    func resume() { session?.resume() }

    private func finish(at end: Date, externalUUID: UUID, title: String, kind: String) async throws {
        // Nothing to save (the session was never adopted) must not read as "saved".
        guard let session, let builder else { throw CocoaError(.featureUnsupported) }
        defer { tearDown() }
        session.end()
        try await builder.endCollection(at: end)
        try await builder.addMetadata([
            HKMetadataKeyExternalUUID: externalUUID.uuidString,
            // What Fitness shows as the title — the iPhone path does the same.
            HKMetadataKeyWorkoutBrandName: title,
            // Read by the iPhone's recovery drain, which skips any session kind.
            Self.sessionKindKey: kind
        ])
        _ = try await builder.finishWorkout()
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        tearDown()
    }

    /// Reconnects a session a previous process left running (crash recovery,
    /// docs/watch-workout-recovery.md). Delegates first, then the data source, so
    /// already-buffered samples are not dropped.
    func adopt(_ recovered: HKWorkoutSession) {
        guard session == nil else { return }
        attach(session: recovered, builder: recovered.associatedWorkoutBuilder())
    }

    private func attach(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        session.delegate = self
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: session.workoutConfiguration
        )
        self.session = session
        self.builder = builder
    }

    private func tearDown() {
        session = nil
        builder = nil
    }
}

extension WatchConditioningWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            print("Conditioning: workout session failed — \(message)")
            self.onSessionFailed?()
        }
    }
}

extension WatchConditioningWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let value = workoutBuilder.statistics(for: heartRateType)?
                .mostRecentQuantity()?
                .doubleValue(for: .count().unitDivided(by: .minute())) else { return }
        // Only the plain value crosses the hop.
        let bpm = Int(value.rounded())
        Task { @MainActor in self.onHeartRate?(bpm) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
