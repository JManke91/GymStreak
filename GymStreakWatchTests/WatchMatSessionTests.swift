//
//  WatchMatSessionTests.swift
//  GymStreakWatchTests
//
//  Positioning ticket 05 (docs/fight-conditioning.md, "Mat sessions on the
//  watch"): the heart-rate tally, the documented zone-time intensity rule, and
//  the recorder — start, end into a review, one-tap intensity, save to the
//  outbox whether or not Apple Health saved it, and crash recovery.
//

import Foundation
import Testing
import HealthKit
import WatchKit
@testable import GymStreakWatch_Watch_App

@MainActor
private final class RecordingMatWorkout: MatSessionWorkoutRecording {
    var onHeartRate: ((Int) -> Void)?
    var onSessionFailed: (() -> Void)?
    var failsToSave = false
    private(set) var startedSports: [String] = []
    private(set) var finishes: [(end: Date, id: UUID, title: String)] = []
    private(set) var pauses = 0
    private(set) var discards = 0

    func start(sport: String, at date: Date) async throws { startedSports.append(sport) }
    func pause() { pauses += 1 }
    func resume() {}
    func finishMatSession(at end: Date, externalUUID: UUID, title: String) async throws {
        finishes.append((end, externalUUID, title))
        if failsToSave { throw CocoaError(.fileWriteUnknown) }
    }
    func discard() { discards += 1 }
}

@Suite @MainActor
struct WatchMatSessionTests {

    private let zones = WatchMatIntensityZones(moderateFromBPM: 140, hardFromBPM: 165)
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// One sample every 5 s for `seconds`, `bpm(t)` at session time t.
    private func tally(seconds: Int, zones: WatchMatIntensityZones?, bpm: (Int) -> Int) -> MatHeartRateTally {
        var tally = MatHeartRateTally()
        for t in stride(from: 0, through: seconds, by: 5) {
            tally.record(bpm(t), at: TimeInterval(t), zones: zones)
        }
        return tally
    }

    // MARK: - Tally

    @Test("Average is time-weighted and the maximum is the highest sample")
    func tallyAverageAndMaximum() {
        var tally = MatHeartRateTally()
        tally.record(100, at: 0, zones: nil)
        tally.record(160, at: 10, zones: nil)   // 100 held for 10 s
        tally.close(at: 15, zones: nil)          // 160 held for 5 s
        #expect(tally.measuredSeconds == 15)
        #expect(tally.average == 120)            // (100·10 + 160·5) / 15
        #expect(tally.maximum == 160)
    }

    @Test("A gap longer than the cap counts only the cap at the last value")
    func tallyCapsGaps() {
        var tally = MatHeartRateTally()
        tally.record(170, at: 0, zones: zones)
        tally.record(120, at: 300, zones: zones)  // sensor dropout
        #expect(tally.measuredSeconds == MatHeartRateTally.maximumGap)
        #expect(tally.hardSeconds == MatHeartRateTally.maximumGap)
    }

    @Test("Time is credited to the band of the sample that held it")
    func tallyBands() {
        var tally = MatHeartRateTally()
        tally.record(120, at: 0, zones: zones)   // below
        tally.record(140, at: 10, zones: zones)  // moderate from 140
        tally.record(165, at: 20, zones: zones)  // hard from 165
        tally.close(at: 30, zones: zones)
        tally.close(at: 30, zones: zones)        // idempotent
        #expect(tally.measuredSeconds == 30)
        #expect(tally.moderateSeconds == 10)
        #expect(tally.hardSeconds == 10)
    }

    // MARK: - The zone-time rule

    @Test("No zones → no suggestion, however hard the session")
    func noZonesNoSuggestion() {
        let tally = tally(seconds: 1_800, zones: nil) { _ in 180 }
        #expect(MatIntensitySuggestion.suggest(from: tally, zones: nil) == nil)
    }

    @Test("Under five minutes of heart rate → no suggestion")
    func tooLittleHeartRate() {
        let tally = tally(seconds: 240, zones: zones) { _ in 180 }
        #expect(MatIntensitySuggestion.suggest(from: tally, zones: zones) == nil)
    }

    @Test("20 % hard → hard sparring; 40 % above aerobic → moderate; else drilling")
    func zoneTimeRule() {
        // 100 s cycles: 20 s hard, rest below → exactly the hard share.
        let hard = tally(seconds: 1_000, zones: zones) { $0 % 100 < 20 ? 170 : 120 }
        #expect(MatIntensitySuggestion.suggest(from: hard, zones: zones) == .hardSparring)

        // 15 s hard + 25 s moderate per 100 s: hard 15 %, above aerobic 40 %.
        let moderate = tally(seconds: 1_000, zones: zones) { t in
            switch t % 100 { case ..<15: 170; case ..<40: 150; default: 120 }
        }
        #expect(MatIntensitySuggestion.suggest(from: moderate, zones: zones) == .moderate)

        // 35 % moderate, nothing hard.
        let drilling = tally(seconds: 1_000, zones: zones) { $0 % 100 < 35 ? 150 : 120 }
        #expect(MatIntensitySuggestion.suggest(from: drilling, zones: zones) == .drilling)
    }

    // MARK: - The recorder

    private func makeRecorder(
        clock: Clock,
        outbox: WatchMatSessionOutbox? = nil,
        checkpoints: WatchMatSessionCheckpointStore? = nil,
        zones: WatchMatIntensityZones? = nil
    ) -> (WatchMatSessionViewModel, RecordingMatWorkout) {
        let workout = RecordingMatWorkout()
        let recorder = WatchMatSessionViewModel(
            workout: workout,
            checkpoints: checkpoints,
            outbox: outbox,
            zones: { zones },
            isOtherWorkoutActive: { false },
            play: { _ in },
            now: { clock.now }
        )
        return (recorder, workout)
    }

    /// Feeds a sample every 5 s of wall time for `seconds`.
    private func train(_ workout: RecordingMatWorkout, _ recorder: WatchMatSessionViewModel, clock: Clock, seconds: Int, bpm: Int) {
        for _ in stride(from: 0, to: seconds, by: 5) {
            workout.onHeartRate?(bpm)
            clock.now = clock.now.addingTimeInterval(5)
        }
        recorder.tick()
    }

    @Test("A session ended under a minute is discarded and queues nothing")
    func shortSessionDiscarded() async {
        let clock = Clock(start)
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, workout) = makeRecorder(clock: clock, outbox: outbox)
        await recorder.start(.boxing)
        #expect(workout.startedSports == ["boxing"])
        clock.now = start.addingTimeInterval(30)
        recorder.end()
        #expect(recorder.state == .finished(.notSaved))
        #expect(workout.discards == 1)
        #expect(outbox.pending.isEmpty)
    }

    @Test("Ending opens the review with the suggestion; one tap changes it; save queues it once")
    func reviewAndSave() async throws {
        let clock = Clock(start)
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, workout) = makeRecorder(clock: clock, outbox: outbox, zones: zones)
        await recorder.start(.bjj)
        train(workout, recorder, clock: clock, seconds: 600, bpm: 175)
        recorder.end()

        guard case .reviewing(let review) = recorder.state else {
            Issue.record("expected the review, got \(recorder.state)"); return
        }
        #expect(review.duration == 600)
        #expect(review.averageHeartRate == 175)
        #expect(review.maximumHeartRate == 175)
        #expect(review.suggested == .hardSparring)
        #expect(recorder.selectedIntensity == .hardSparring)
        #expect(workout.pauses == 1)       // the Health session stops at the end, not at Save
        #expect(outbox.pending.isEmpty)    // nothing leaves before the user confirms

        recorder.selectedIntensity = .moderate
        clock.now = clock.now.addingTimeInterval(20)  // the user takes a moment
        await recorder.save()

        #expect(recorder.state == .finished(.saved))
        let finish = try #require(workout.finishes.first)
        #expect(finish.end == start.addingTimeInterval(600))
        #expect(finish.title == "BJJ")
        let queued = try #require(outbox.pending.first)
        #expect(outbox.pending.count == 1)
        #expect(queued.id == finish.id)
        #expect(queued.sport == "bjj")
        #expect(queued.intensity == "moderate")
        #expect(queued.startTime == start)
        #expect(queued.endTime == start.addingTimeInterval(600))
        #expect(queued.isSavedToHealth)
    }

    @Test("Without zones the user picks; Save waits for a pick")
    func noProfileUserPicks() async {
        let clock = Clock(start)
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, workout) = makeRecorder(clock: clock, outbox: outbox, zones: nil)
        await recorder.start(.muayThai)
        train(workout, recorder, clock: clock, seconds: 900, bpm: 175)
        recorder.end()
        guard case .reviewing(let review) = recorder.state else {
            Issue.record("expected the review"); return
        }
        #expect(review.suggested == nil)
        #expect(recorder.selectedIntensity == nil)
        await recorder.save()
        #expect(outbox.pending.isEmpty)
        recorder.selectedIntensity = .drilling
        await recorder.save()
        #expect(outbox.pending.map(\.intensity) == ["drilling"])
    }

    @Test("A failed Health save still reaches the outbox, as not in Health")
    func failedHealthSaveStillQueued() async {
        let clock = Clock(start)
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, workout) = makeRecorder(clock: clock, outbox: outbox)
        workout.failsToSave = true
        await recorder.start(.wrestling)
        clock.now = start.addingTimeInterval(120)
        recorder.end()
        recorder.selectedIntensity = .moderate
        await recorder.save()
        #expect(recorder.state == .finished(.failed))
        #expect(outbox.pending.map(\.isSavedToHealth) == [false])
    }

    @Test("Paused time is not part of the duration")
    func pauseExcluded() async throws {
        let clock = Clock(start)
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, _) = makeRecorder(clock: clock, outbox: outbox)
        await recorder.start(.mma)
        clock.now = start.addingTimeInterval(300)
        recorder.pause()
        clock.now = start.addingTimeInterval(500)
        recorder.resume()
        clock.now = start.addingTimeInterval(800)
        recorder.end()
        recorder.selectedIntensity = .moderate
        await recorder.save()
        let queued = try #require(outbox.pending.first)
        #expect(queued.endTime.timeIntervalSince(queued.startTime) == 600)
    }

    @Test("A relaunch resumes the running session where the clock says, without a new start")
    func recoveryResumesRunning() async throws {
        let directory = tempDirectory()
        let clock = Clock(start)
        let (first, _) = makeRecorder(clock: clock, checkpoints: WatchMatSessionCheckpointStore(directory: directory), zones: zones)
        await first.start(.bjj)

        clock.now = start.addingTimeInterval(400)
        let checkpoint = try #require(WatchMatSessionCheckpointStore(directory: directory).load())
        let (second, workout) = makeRecorder(clock: clock, checkpoints: WatchMatSessionCheckpointStore(directory: directory))
        second.resumeRecovered(from: checkpoint)
        #expect(second.state == .running)
        #expect(second.sport == .bjj)
        #expect(second.elapsed == 400)
        #expect(second.isRunnerPresented)
        #expect(workout.startedSports.isEmpty)
        #expect(second.heartRateReading == .measuring)
    }

    @Test("A relaunch on the review screen comes back to the review and saves the same session")
    func recoveryResumesReview() async throws {
        let directory = tempDirectory()
        let clock = Clock(start)
        let (first, firstWorkout) = makeRecorder(clock: clock, checkpoints: WatchMatSessionCheckpointStore(directory: directory), zones: zones)
        await first.start(.boxing)
        train(firstWorkout, first, clock: clock, seconds: 600, bpm: 150)
        first.end()
        guard case .reviewing(let before) = first.state else { Issue.record("expected the review"); return }

        clock.now = clock.now.addingTimeInterval(3_600)
        let checkpoint = try #require(WatchMatSessionCheckpointStore(directory: directory).load())
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (second, workout) = makeRecorder(
            clock: clock, outbox: outbox, checkpoints: WatchMatSessionCheckpointStore(directory: directory)
        )
        second.resumeRecovered(from: checkpoint)
        #expect(second.state == .reviewing(before))
        #expect(second.selectedIntensity == .moderate)

        await second.save()
        let finish = try #require(workout.finishes.first)
        #expect(finish.end == start.addingTimeInterval(600))
        #expect(finish.id == checkpoint.externalUUID)
        #expect(outbox.pending.map(\.id) == [checkpoint.externalUUID])
        #expect(WatchMatSessionCheckpointStore(directory: directory).load() == nil)
    }

    // MARK: - Outbox and wire

    @Test("The mat outbox survives a relaunch, keeps its own file and leaves only on its ack")
    func outboxDurable() {
        let directory = tempDirectory()
        let session = WatchCompletedMatSession(
            id: UUID(), startTime: start, endTime: start.addingTimeInterval(3_600),
            sport: "bjj", intensity: "hardSparring", isSavedToHealth: true
        )
        WatchMatSessionOutbox(directory: directory).enqueue(session)
        WatchMatSessionOutbox(directory: directory).enqueue(session)
        #expect(WatchConditioningOutbox(directory: directory).pending.isEmpty)

        let relaunched = WatchMatSessionOutbox(directory: directory)
        #expect(relaunched.pending == [session])
        relaunched.acknowledge(id: UUID())
        #expect(relaunched.pending.count == 1)
        relaunched.acknowledge(id: session.id)
        #expect(WatchMatSessionOutbox(directory: directory).pending.isEmpty)
    }

    @Test("The wire round trip carries the conditioning id key, so the shared ack covers it")
    func wireRoundTrip() throws {
        let session = WatchCompletedMatSession(
            id: UUID(), startTime: start, endTime: start.addingTimeInterval(1_800),
            sport: "muayThai", intensity: "drilling", isSavedToHealth: false
        )
        let payload = try #require(WatchConditioningWire.userInfo(for: session))
        #expect(payload[WatchConditioningWire.completedSessionIdKey] as? String == session.id.uuidString)
        #expect(payload[WatchConditioningWire.completedSessionKey] == nil)
        #expect(WatchConditioningWire.completedMatSession(from: payload) == session)
        #expect(WatchConditioningWire.completedSession(from: payload) == nil)
    }

    @Test("The sport maps to the iPhone's Apple Health activity types")
    func activityTypes() {
        #expect(WatchConditioningWorkoutManager.configuration(forSport: "bjj").activityType == .martialArts)
        #expect(WatchConditioningWorkoutManager.configuration(forSport: "muayThai").activityType == .martialArts)
        #expect(WatchConditioningWorkoutManager.configuration(forSport: "boxing").activityType == .boxing)
        #expect(WatchConditioningWorkoutManager.configuration(forSport: "wrestling").activityType == .wrestling)
        #expect(WatchConditioningWorkoutManager.configuration(forSport: "other").activityType == .other)
        #expect(WatchConditioningWorkoutManager.configuration(forSport: "bjj").locationType == .indoor)
    }
}
