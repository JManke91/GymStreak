//
//  WatchConditioningRunViewModelTests.swift
//  GymStreakWatchTests
//
//  Ticket 06 (docs/fight-conditioning.md): the watch runner against a fake
//  HealthKit recorder and a hand-driven clock — nothing saved before the first
//  effort, one save at the timeline's end, pauses freeze time, a recovered
//  session resumes without replaying cues, the zone applies only where the
//  iPhone put one, and a sustained drift nudges.
//

import Foundation
import Testing
import WatchKit
@testable import GymStreakWatch_Watch_App

@MainActor
private final class FakeWorkoutRecorder: ConditioningWorkoutRecording {
    var onHeartRate: ((Int) -> Void)?
    var onSessionFailed: (() -> Void)?
    private(set) var started: [String] = []
    private(set) var finishedAt: [Date] = []
    private(set) var discards = 0
    private(set) var pauses = 0

    func start(modality: String, at date: Date) async throws { started.append(modality) }
    func pause() { pauses += 1 }
    func resume() {}
    func finish(at end: Date, externalUUID: UUID, title: String) async throws { finishedAt.append(end) }
    func discard() { discards += 1 }
}

@Suite @MainActor
struct WatchConditioningRunViewModelTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// 60 s warm-up, one 30 s work phase, 60 s cool-down.
    private func intervalSession(zone: WatchHeartRateZone? = nil) -> WatchConditioningSession {
        WatchConditioningSession(
            sessionType: "lactic30", energySystem: "lactic", modalities: ["rower"], volume: 1,
            isSuggestedToday: true,
            phases: [
                ConditioningPhase(kind: .warmUp, duration: 60, effort: .easy),
                ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 1, roundsPerSet: 1),
                ConditioningPhase(kind: .coolDown, duration: 60, effort: .easy)
            ],
            heartRateZone: zone
        )
    }

    private func steadySession(zone: WatchHeartRateZone?) -> WatchConditioningSession {
        WatchConditioningSession(
            sessionType: "aerobicBase", energySystem: "aerobic", modalities: ["run"], volume: 30,
            isSuggestedToday: true,
            phases: [ConditioningPhase(kind: .steady, duration: 1800, effort: .conversational)],
            heartRateZone: zone
        )
    }

    private final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    private func makeRunner(
        clock: Clock,
        haptics: @escaping (WKHapticType) -> Void = { _ in }
    ) -> (WatchConditioningRunViewModel, FakeWorkoutRecorder) {
        let recorder = FakeWorkoutRecorder()
        let runner = WatchConditioningRunViewModel(
            workout: recorder,
            checkpoints: WatchConditioningCheckpointStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            isOtherWorkoutActive: { false },
            play: haptics,
            now: { clock.now }
        )
        return (runner, recorder)
    }

    @Test("Ending during the warm-up saves nothing and discards the HealthKit session")
    func endInWarmUpSavesNothing() async {
        let clock = Clock(start)
        let (runner, recorder) = makeRunner(clock: clock)
        await runner.start(intervalSession(), modality: "rower")
        #expect(recorder.started == ["rower"])

        clock.now = start.addingTimeInterval(45)
        await runner.end()
        #expect(recorder.discards == 1)
        #expect(recorder.finishedAt.isEmpty)
        #expect(runner.state == .finished(.init(isComplete: false, elapsed: 45, health: .notSaved)))
    }

    @Test("Ending after the first effort saves once, at the moment it ended")
    func endAfterEffortSaves() async {
        let clock = Clock(start)
        let (runner, recorder) = makeRunner(clock: clock)
        await runner.start(intervalSession(), modality: "rower")
        clock.now = start.addingTimeInterval(75)
        await runner.end()
        #expect(recorder.finishedAt == [start.addingTimeInterval(75)])
        #expect(runner.state == .finished(.init(isComplete: false, elapsed: 75, health: .saved)))
    }

    @Test("A paused session does not advance")
    func pauseFreezes() async {
        let clock = Clock(start)
        let (runner, recorder) = makeRunner(clock: clock)
        await runner.start(intervalSession(), modality: "rower")
        clock.now = start.addingTimeInterval(20)
        runner.pause()
        clock.now = start.addingTimeInterval(500)
        runner.tick()
        #expect(runner.elapsed == 20)
        #expect(recorder.pauses == 1)
        await runner.end()
    }

    @Test("A recovered session resumes where the wall clock says, replaying no cue, and finishes at the timeline's end")
    func recoveredSessionFinishesAtTimelineEnd() async throws {
        let clock = Clock(start.addingTimeInterval(500))
        var played: [WKHapticType] = []
        let (runner, recorder) = makeRunner(clock: clock) { played.append($0) }
        var sessionClock = ConditioningClock()
        sessionClock.start(at: start)

        runner.resumeRecovered(from: WatchConditioningCheckpoint(
            session: intervalSession(), modality: "rower", clock: sessionClock, externalUUID: UUID()
        ))
        runner.tick()
        // `tick()` finishes in a spawned task; wait for it with a bound, not a yield count.
        for _ in 0..<200 where recorder.finishedAt.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        #expect(played.isEmpty)
        #expect(recorder.finishedAt == [start.addingTimeInterval(150)])
        guard case .finished(let summary) = runner.state else {
            Issue.record("expected a finished state, got \(runner.state)")
            return
        }
        #expect(summary.isComplete)
    }

    @Test("The zone applies only to conversational phases the iPhone gave a range; RPE-only shows none")
    func zoneOnlyWhereSynced() async {
        let clock = Clock(start)
        let zone = WatchHeartRateZone(lowerBPM: 120, upperBPM: 145)

        let (steady, _) = makeRunner(clock: clock)
        await steady.start(steadySession(zone: zone), modality: "run")
        #expect(steady.zone == zone)
        await steady.end()

        let (rpeOnly, _) = makeRunner(clock: clock)
        await rpeOnly.start(steadySession(zone: nil), modality: "run")
        #expect(rpeOnly.zone == nil)
        await rpeOnly.end()

        let (intervals, _) = makeRunner(clock: clock)
        await intervals.start(intervalSession(zone: zone), modality: "rower")
        #expect(intervals.zone == nil)
        await intervals.end()
    }

    @Test("A sustained drift above the range nudges with a gentle haptic")
    func driftNudges() async {
        let clock = Clock(start)
        var played: [WKHapticType] = []
        let recorder = FakeWorkoutRecorder()
        let runner = WatchConditioningRunViewModel(
            workout: recorder, checkpoints: nil, isOtherWorkoutActive: { false },
            play: { played.append($0) }, now: { clock.now }
        )
        await runner.start(steadySession(zone: WatchHeartRateZone(lowerBPM: 120, upperBPM: 145)), modality: "run")
        played.removeAll()

        recorder.onHeartRate?(160)
        clock.now = start.addingTimeInterval(100)
        runner.tick()
        #expect(runner.zoneStatus == .above)
        #expect(played.isEmpty)
        clock.now = start.addingTimeInterval(101)
        runner.tick()
        clock.now = start.addingTimeInterval(102)
        runner.tick()
        #expect(!played.contains(.directionDown))
        clock.now = start.addingTimeInterval(130)
        runner.tick()
        #expect(played.contains(.directionDown))
        await runner.end()
    }

    @Test("Display values: the countdown page, the 3-2-1 before the effort, and the round dots")
    func displayValues() async {
        let clock = Clock(start)
        let (runner, _) = makeRunner(clock: clock)
        await runner.start(intervalSession(), modality: "rower")

        clock.now = start.addingTimeInterval(56.5)
        runner.tick()
        #expect(!runner.showsZonePage)
        #expect(runner.leadInCount == nil)
        clock.now = start.addingTimeInterval(57.5)
        runner.tick()
        #expect(runner.leadInCount == 3)

        clock.now = start.addingTimeInterval(70)
        runner.tick()
        #expect(runner.leadInCount == nil)
        #expect(runner.roundProgress?.current == 0)
        #expect(runner.roundProgress?.total == 1)
        #expect(abs(runner.phaseRemainingFraction - 20.0 / 30.0) < 0.001)
        await runner.end()

        let (steady, _) = makeRunner(clock: clock)
        await steady.start(steadySession(zone: nil), modality: "run")
        #expect(steady.showsZonePage)
        await steady.end()
    }

    @Test("Heart rate: measuring until the first sample, missing after 30 s without one, then the value")
    func heartRateReading() async {
        let clock = Clock(start)
        let (runner, recorder) = makeRunner(clock: clock)
        let zone = WatchHeartRateZone(lowerBPM: 120, upperBPM: 145)
        await runner.start(steadySession(zone: zone), modality: "run")

        clock.now = start.addingTimeInterval(10)
        runner.tick()
        #expect(runner.heartRateReading == .measuring)
        // A user with a range is told the reading is coming — not the RPE-only copy.
        #expect(WatchConditioningCopy.zoneInstruction(runner.zoneStatus, reading: runner.heartRateReading, zone: zone)
                == WatchConditioningCopy.zoneInstruction(nil, reading: .measuring, zone: zone))
        #expect(WatchConditioningCopy.zoneInstruction(nil, reading: .measuring, zone: zone)
                != WatchConditioningCopy.zoneInstruction(nil, reading: .measuring, zone: nil))

        clock.now = start.addingTimeInterval(31)
        runner.tick()
        #expect(runner.heartRateReading == .missing)

        recorder.onHeartRate?(130)
        #expect(runner.heartRateReading == .bpm(130))
        await runner.end()
    }

    @Test("A recovered session is measuring again, not missing, for its first 30 s")
    func recoveredSessionMeasuresAgain() {
        let clock = Clock(start.addingTimeInterval(600))
        let (runner, _) = makeRunner(clock: clock)
        var sessionClock = ConditioningClock()
        sessionClock.start(at: start)
        runner.resumeRecovered(from: WatchConditioningCheckpoint(
            session: steadySession(zone: nil), modality: "run", clock: sessionClock, externalUUID: UUID()
        ))
        runner.tick()
        #expect(runner.heartRateReading == .measuring)
        clock.now = start.addingTimeInterval(631)
        runner.tick()
        #expect(runner.heartRateReading == .missing)
    }
}
