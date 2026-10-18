//
//  WatchE2EScenarioRunner.swift
//  GymStreakWatch Watch App
//
//  DEBUG-only scripted scenarios an agent launches on the watch simulator
//  instead of tapping through the UI (docs/agent-e2e-verification.md):
//
//      xcrun simctl launch <watch> com.shotat24fps.GymStreak.watchkitapp \
//          -E2E_SCENARIO mat-record -E2E_SPORT bjj -E2E_SECONDS 70
//
//  A scenario a system relaunch must run — watchOS relaunches the app itself
//  after a crash mid-workout, without arguments — is written to the app's
//  defaults beforehand instead, and consumed on read:
//
//      xcrun simctl spawn <watch> defaults write \
//          com.shotat24fps.GymStreak.watchkitapp E2E_SCENARIO mat-finish
//
//  Each step drives the same view model the views drive and logs one
//  `E2E …` line under the `E2E` category, which the harness reads back with
//  `log show`. Scenarios:
//    mat-record  start → wait → end → save → read the Health workout back
//    mat-start   start and keep running (the harness then kills the app)
//    mat-end     start → wait → end, left on the review (then killed)
//    mat-finish  take whatever recovery restored: end it if running, save it
//
//  `-E2E_HEART_RATE <bpm>` feeds that heart rate once a second while a session
//  runs, through the workout manager's `onHeartRate` — the callback the live
//  builder's samples arrive on. The simulator's own samples (~60 bpm) can't be
//  steered, and a zone-based intensity suggestion needs time above the zones.
//

#if DEBUG
import Foundation
import HealthKit
import os

enum WatchE2EScenarioRunner {
    private static let logger = Logger(subsystem: "com.shotat24fps.GymStreak", category: "E2E")

    static func runIfRequested(matSession: WatchMatSessionViewModel, matWorkout: WatchConditioningWorkoutManager) {
        guard let scenario = setting("E2E_SCENARIO") else { return }
        let sport = setting("E2E_SPORT").flatMap(WatchMatSport.init(rawValue:)) ?? .bjj
        let seconds = setting("E2E_SECONDS").flatMap(Double.init) ?? 70
        let heartRate = setting("E2E_HEART_RATE").flatMap(Int.init)
        log("scenario=\(scenario) sport=\(sport.rawValue) seconds=\(Int(seconds)) heartRate=\(heartRate.map(String.init) ?? "sensor")")
        if let heartRate {
            Task { await feedHeartRate(heartRate, to: matWorkout, while: matSession) }
        }
        Task { await run(scenario, sport: sport, seconds: seconds, mat: matSession) }
    }

    private static func feedHeartRate(_ bpm: Int, to workout: WatchConditioningWorkoutManager, while mat: WatchMatSessionViewModel) async {
        // Wait for the session to start, then feed until it stops running.
        while mat.state != .running && mat.state != .paused {
            try? await Task.sleep(for: .milliseconds(500))
        }
        while mat.state == .running || mat.state == .paused {
            workout.onHeartRate?(bpm)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func run(_ scenario: String, sport: WatchMatSport, seconds: Double, mat: WatchMatSessionViewModel) async {
        switch scenario {
        case "mat-record":
            await start(sport, mat: mat)
            try? await Task.sleep(for: .seconds(seconds))
            await endAndSave(mat)
        case "mat-start":
            await start(sport, mat: mat)
        case "mat-end":
            await start(sport, mat: mat)
            try? await Task.sleep(for: .seconds(seconds))
            mat.end()
            logState(mat)
        case "mat-finish":
            // Recovery runs asynchronously after launch; give it a moment.
            for _ in 0..<30 where mat.state == .idle {
                try? await Task.sleep(for: .milliseconds(500))
            }
            log("recovered state=\(describe(mat.state)) sport=\(mat.sport.rawValue) elapsed=\(Int(mat.elapsed))")
            await endAndSave(mat)
        default:
            log("unknown scenario")
        }
    }

    private static func start(_ sport: WatchMatSport, mat: WatchMatSessionViewModel) async {
        await mat.start(sport)
        logState(mat)
        log("zones=\(zones.map { "\($0.moderateFromBPM)/\($0.hardFromBPM)" } ?? "nil")")
    }

    /// The bands the iPhone last sent — what a session started now records against.
    private static var zones: WatchMatIntensityZones? {
        WatchConnectivityManager.shared.conditioningStore.program?.matIntensityZones
    }

    private static func endAndSave(_ mat: WatchMatSessionViewModel) async {
        mat.end()
        logState(mat)
        guard case .reviewing(let review) = mat.state else { return }
        log("review duration=\(Int(review.duration)) avg=\(review.averageHeartRate.map(String.init) ?? "nil") max=\(review.maximumHeartRate.map(String.init) ?? "nil") suggested=\(review.suggested?.rawValue ?? "nil")")
        if mat.selectedIntensity == nil { mat.selectedIntensity = .drilling }
        log("intensity=\(mat.selectedIntensity?.rawValue ?? "nil")")
        await mat.save()
        logState(mat)
        await logLatestHealthWorkout()
    }

    /// The newest workout in this watch's Health store, as Apple Health shows it.
    private static func logLatestHealthWorkout() async {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            guard let workout = try await descriptor.result(for: HKHealthStore()).first else {
                log("health workout=none")
                return
            }
            let kind = workout.metadata?[WatchConditioningWorkoutManager.sessionKindKey] as? String ?? "nil"
            let external = (workout.metadata?[HKMetadataKeyExternalUUID] as? String).flatMap(UUID.init(uuidString:))
            log("health activityType=\(workout.workoutActivityType.rawValue) kind=\(kind) duration=\(Int(workout.duration)) external=\(WatchSyncDiagnostics.shortID(external))")
        } catch {
            log("health query failed: \(error.localizedDescription)")
        }
    }

    private static func logState(_ mat: WatchMatSessionViewModel) {
        log("state=\(describe(mat.state)) elapsed=\(Int(mat.elapsed)) heartRate=\(mat.heartRate.map(String.init) ?? "nil")")
    }

    private static func describe(_ state: WatchMatSessionViewModel.State) -> String {
        switch state {
        case .idle: "idle"
        case .couldNotStart: "couldNotStart"
        case .running: "running"
        case .paused: "paused"
        case .reviewing: "reviewing"
        case .saving: "saving"
        case .finished(let health): "finished-\(health)"
        }
    }

    /// A `-NAME value` launch argument or a `defaults write` value; the latter is
    /// removed once read so it runs on one launch only.
    private static func setting(_ name: String) -> String? {
        let value = UserDefaults.standard.string(forKey: name)
        UserDefaults.standard.removeObject(forKey: name)
        return value
    }

    private static func log(_ message: String) {
        logger.notice("E2E \(message, privacy: .public)")
    }
}
#endif
