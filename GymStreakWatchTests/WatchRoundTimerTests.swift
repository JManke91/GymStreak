//
//  WatchRoundTimerTests.swift
//  GymStreakWatchTests
//
//  Positioning ticket 07 (docs/fight-conditioning.md, "Round timer"): the
//  shared configuration's expansion into phases, the end-of-round warning, and
//  the mat-session recorder running a round plan — haptics, the automatic end
//  into the review, discard without a trace, save as a mat session, recovery.
//

import Foundation
import Testing
import WatchKit
@testable import GymStreakWatch_Watch_App

@MainActor
private final class RoundTimerWorkout: MatSessionWorkoutRecording {
    var onHeartRate: ((Int) -> Void)?
    var onSessionFailed: (() -> Void)?
    private(set) var startedSports: [String] = []
    private(set) var finishes = 0
    private(set) var discards = 0

    func start(sport: String, at date: Date) async throws { startedSports.append(sport) }
    func pause() {}
    func resume() {}
    func finishMatSession(at end: Date, externalUUID: UUID, title: String) async throws { finishes += 1 }
    func discard() { discards += 1 }
}

@Suite @MainActor
struct WatchRoundTimerTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private final class Clock { var now: Date; init(_ now: Date) { self.now = now } }
    private final class Haptics { var played: [WKHapticType] = [] }

    /// 2 × 60 s rounds, 15 s rest, warning 10 s: warning at 50, rest at 60, lead-in
    /// 72-73-74, round 2 at 75, warning at 125, the end at 135.
    private let custom = RoundTimerConfiguration(
        preset: .custom, customRoundDuration: 60, customRestDuration: 15, rounds: 2, warning: 10
    )

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Shared copy

    @Test("The round timer configuration is identical in both targets")
    func sharedCopiesMatch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let iOSCopy = try String(
            contentsOf: root.appendingPathComponent("GymStreak/Domain/Models/Conditioning/RoundTimerConfiguration.swift"),
            encoding: .utf8
        )
        let watchCopy = try String(
            contentsOf: root.appendingPathComponent("GymStreakWatch Watch App/Models/Conditioning/RoundTimerConfiguration.swift"),
            encoding: .utf8
        )
        #expect(iOSCopy == watchCopy, "RoundTimerConfiguration.swift drifted from its iOS twin")
    }

    // MARK: - Configuration

    @Test("Three rounds expand to round, rest, round, rest, round")
    func phasesWithRests() {
        var configuration = RoundTimerConfiguration.default
        configuration.rounds = 3
        let phases = configuration.phases()
        #expect(phases.map(\.kind) == [.work, .rest, .work, .rest, .work])
        #expect(phases.map(\.round) == [1, 1, 2, 2, 3])
        #expect(phases.allSatisfy { $0.roundsPerSet == 3 })
        #expect(phases.filter { $0.kind == .work }.allSatisfy { $0.duration == 300 })
        #expect(phases.filter { $0.kind == .rest }.allSatisfy { $0.duration == 60 })
        #expect(configuration.totalDuration == TimeInterval(17 * 60))
    }

    @Test("A rest of 0 leaves the rests out")
    func zeroRest() {
        var configuration = custom
        configuration.customRestDuration = 0
        #expect(configuration.phases().map(\.kind) == [.work, .work])
    }

    @Test("Open-ended runs 99 rounds with no round total")
    func openEnded() {
        var configuration = RoundTimerConfiguration.default
        configuration.rounds = nil
        let work = configuration.phases().filter { $0.kind == .work }
        #expect(work.count == RoundTimerConfiguration.openEndedRoundCount)
        #expect(work.allSatisfy { $0.roundsPerSet == nil })
        #expect(configuration.totalDuration == nil)
    }

    @Test("Presets fix the lengths and name the sport")
    func presets() {
        #expect(RoundTimerPreset.muayThai.roundDuration == 180)
        #expect(RoundTimerPreset.muayThai.restDuration == 120)
        #expect(RoundTimerPreset.custom.roundDuration == nil)
        #expect(RoundTimerPreset.custom.matSportRawValue == "other")
        #expect(RoundTimerPreset.allCases.allSatisfy { WatchMatSport(rawValue: $0.matSportRawValue) != nil })
    }

    // MARK: - Warning

    @Test("The warning comes 10 s before each round ends")
    func warningOffsets() {
        let timeline = ConditioningTimeline(phases: custom.phases())
        #expect(timeline.warningOffsets(before: 10) == [50, 125])
        #expect(timeline.warningOffsets(before: 0).isEmpty)
        #expect(timeline.warningOffsets(before: 60).isEmpty)
    }

    @Test("Crossing a warning emits it; a catch-up gap emits nothing")
    func evaluatorWarning() {
        let timeline = ConditioningTimeline(phases: custom.phases())
        #expect(ConditioningCueEvaluator.cues(in: timeline, from: 49.6, to: 50.1, warning: 10) == [.warning])
        #expect(ConditioningCueEvaluator.cues(in: timeline, from: 49.6, to: 50.1).isEmpty)
        #expect(ConditioningCueEvaluator.cues(in: timeline, from: 45, to: 52, warning: 10).isEmpty)
        // In time order with the phase cues.
        #expect(ConditioningCueEvaluator.cues(in: timeline, from: 59, to: 60, warning: 10) == [.recoveryStart])
        #expect(ConditioningCueEvaluator.cues(in: timeline, from: 124, to: 126, warning: 10) == [.warning])
    }

    // MARK: - The recorder running rounds

    private func makeRecorder(
        clock: Clock,
        haptics: Haptics = Haptics(),
        outbox: WatchMatSessionOutbox? = nil,
        checkpoints: WatchMatSessionCheckpointStore? = nil
    ) -> (WatchMatSessionViewModel, RoundTimerWorkout) {
        let workout = RoundTimerWorkout()
        let recorder = WatchMatSessionViewModel(
            workout: workout,
            checkpoints: checkpoints,
            outbox: outbox,
            zones: { nil },
            isOtherWorkoutActive: { false },
            play: { haptics.played.append($0) },
            now: { clock.now }
        )
        return (recorder, workout)
    }

    /// Ticks every 0.5 s of session time up to `seconds` after the start.
    private func run(_ recorder: WatchMatSessionViewModel, clock: Clock, to seconds: TimeInterval) {
        while clock.now.timeIntervalSince(start) < seconds {
            clock.now = clock.now.addingTimeInterval(0.5)
            recorder.tick()
        }
    }

    @Test("A preset starts the workout as its sport; custom as other")
    func startsAsPresetSport() async {
        let (boxing, boxingWorkout) = makeRecorder(clock: Clock(start))
        var configuration = RoundTimerConfiguration.default
        configuration.preset = .boxing
        await boxing.startRoundTimer(configuration)
        #expect(boxingWorkout.startedSports == ["boxing"])
        #expect(boxing.sport == .boxing)
        #expect(boxing.isRoundTimer)
        #expect(boxing.roundPosition?.phase.round == 1)

        let (other, otherWorkout) = makeRecorder(clock: Clock(start))
        await other.startRoundTimer(custom)
        #expect(otherWorkout.startedSports == ["other"])
    }

    @Test("Rounds play warning, rest, 3-2-1 and start, then end into the review on their own")
    func hapticsAndAutomaticEnd() async {
        let clock = Clock(start)
        let haptics = Haptics()
        let (recorder, _) = makeRecorder(clock: clock, haptics: haptics)
        await recorder.startRoundTimer(custom)
        #expect(haptics.played == [.start])

        run(recorder, clock: clock, to: 76)
        #expect(haptics.played == [.start, .notification, .stop, .click, .click, .click, .start])
        #expect(recorder.roundPosition?.phase.round == 2)
        #expect(recorder.completedRounds == 1)

        run(recorder, clock: clock, to: 136)
        #expect(haptics.played.suffix(2) == [.notification, .stop])
        guard case .reviewing(let review) = recorder.state else {
            Issue.record("expected the review, got \(recorder.state)"); return
        }
        #expect(review.duration == 135)
        #expect(review.rounds == 2)
        #expect(recorder.completedRounds == 2)
        #expect(recorder.roundPosition == nil)
    }

    @Test("A paused timer plays nothing and does not end")
    func pausedIsSilent() async {
        let clock = Clock(start)
        let haptics = Haptics()
        let (recorder, _) = makeRecorder(clock: clock, haptics: haptics)
        await recorder.startRoundTimer(custom)
        run(recorder, clock: clock, to: 45)
        recorder.pause()
        run(recorder, clock: clock, to: 300)
        #expect(haptics.played == [.start])
        #expect(recorder.state == .paused)
    }

    @Test("Don't save discards the workout, clears the checkpoint and queues nothing")
    func discardLeavesNoTrace() async {
        let clock = Clock(start)
        let directory = tempDirectory()
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, workout) = makeRecorder(
            clock: clock, outbox: outbox, checkpoints: WatchMatSessionCheckpointStore(directory: directory)
        )
        await recorder.startRoundTimer(custom)
        run(recorder, clock: clock, to: 136)
        recorder.discard()
        #expect(recorder.state == .finished(.discarded))
        #expect(workout.discards == 1)
        #expect(workout.finishes == 0)
        #expect(outbox.pending.isEmpty)
        #expect(WatchMatSessionCheckpointStore(directory: directory).load() == nil)
    }

    @Test("Save as mat session queues one entry with the preset's sport")
    func saveAsMatSession() async throws {
        let clock = Clock(start)
        let outbox = WatchMatSessionOutbox(directory: tempDirectory())
        let (recorder, workout) = makeRecorder(clock: clock, outbox: outbox)
        await recorder.startRoundTimer(custom)
        run(recorder, clock: clock, to: 136)
        recorder.selectedIntensity = .moderate
        await recorder.save()
        #expect(recorder.state == .finished(.saved))
        #expect(workout.finishes == 1)
        #expect(outbox.pending.count == 1)
        let queued = try #require(outbox.pending.first)
        #expect(queued.sport == "other")
        #expect(queued.endTime.timeIntervalSince(queued.startTime) == 135)
    }

    @Test("A relaunch rebuilds the rounds from the checkpoint and replays no cue")
    func recoveryRebuildsTimeline() async throws {
        let directory = tempDirectory()
        let clock = Clock(start)
        let (first, _) = makeRecorder(clock: clock, checkpoints: WatchMatSessionCheckpointStore(directory: directory))
        await first.startRoundTimer(custom)

        clock.now = start.addingTimeInterval(55)   // past round 1's warning
        let checkpoint = try #require(WatchMatSessionCheckpointStore(directory: directory).load())
        #expect(checkpoint.rounds == custom)

        let haptics = Haptics()
        let (second, _) = makeRecorder(
            clock: clock, haptics: haptics, checkpoints: WatchMatSessionCheckpointStore(directory: directory)
        )
        second.resumeRecovered(from: checkpoint)
        #expect(second.isRoundTimer)
        #expect(second.roundPosition?.phase.round == 1)
        second.tick()
        #expect(haptics.played.isEmpty)
        run(second, clock: clock, to: 61)
        #expect(haptics.played == [.stop])
    }

    @Test("A plain mat session has no round plan")
    func plainSessionHasNoPlan() async {
        let (recorder, _) = makeRecorder(clock: Clock(start))
        await recorder.start(.bjj)
        #expect(!recorder.isRoundTimer)
        #expect(recorder.roundPosition == nil)
        #expect(recorder.completedRounds == 0)
    }

    // MARK: - Settings

    @Test("The last configuration is remembered; the default the first time")
    func settingsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = WatchRoundTimerSettingsStore(defaults: defaults)
        #expect(store.load() == .default)
        store.save(custom)
        #expect(WatchRoundTimerSettingsStore(defaults: defaults).load() == custom)
    }

    @Test("Starting a round timer remembers its configuration for the next setup")
    func startRemembersTheConfiguration() async {
        let defaults = UserDefaults(suiteName: "WatchRoundTimerTests.\(UUID().uuidString)")!
        let store = WatchRoundTimerSettingsStore(defaults: defaults)
        let recorder = WatchMatSessionViewModel(
            workout: RoundTimerWorkout(),
            checkpoints: nil,
            outbox: nil,
            zones: { nil },
            isOtherWorkoutActive: { false },
            roundTimerSettings: store,
            play: { _ in },
            now: { Date(timeIntervalSinceReferenceDate: 50_000) }
        )
        #expect(recorder.lastRoundTimerConfiguration == .default)

        let configuration = RoundTimerConfiguration(
            preset: .muayThai, customRoundDuration: 90, customRestDuration: 30, rounds: nil, warning: 10
        )
        await recorder.startRoundTimer(configuration)
        #expect(recorder.lastRoundTimerConfiguration == configuration)
        #expect(store.load() == configuration)
    }
}
