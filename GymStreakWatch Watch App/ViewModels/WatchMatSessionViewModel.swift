//
//  WatchMatSessionViewModel.swift
//  GymStreakWatch Watch App
//
//  Records a mat session on the watch (positioning ticket 05,
//  docs/fight-conditioning.md "Mat sessions on the watch"): an open-ended live
//  workout with elapsed time and heart rate, then a review with duration,
//  average and maximum heart rate and a suggested intensity the user confirms.
//
//  Reuses the conditioning runner's plumbing rather than a second copy: the
//  same HealthKit manager (`MatSessionWorkoutRecording`), the pause-aware
//  `ConditioningClock`, the checkpoint store, the outbox and its transport.
//  Never a conditioning program session — nothing here reads the offer's targets.
//

import Foundation
import Observation
import WatchKit

@Observable
@MainActor
final class WatchMatSessionViewModel {

    // `HealthOutcome`, `Review`, `State` and `heartRateReading`: +State.swift.
    // The round timer's entry point and read-outs: +Rounds.swift.

    /// Shorter than this is a mis-tap: ending discards it, nothing is saved.
    static let minimumDuration: TimeInterval = 60
    /// How often the running tally is checkpointed (session time).
    static let checkpointInterval: TimeInterval = 60

    private(set) var state: State = .idle
    private(set) var sport: WatchMatSport = .bjj
    private(set) var elapsed: TimeInterval = 0
    private(set) var heartRate: Int?
    /// Preset to the suggestion; the review's one tap changes it.
    var selectedIntensity: WatchMatIntensity?
    var isRunnerPresented = false
    /// The round timer's plan (positioning ticket 07); `nil` for a plain mat session.
    private(set) var rounds: RoundTimerConfiguration?
    /// Where the round timer is; `nil` without a plan or once its timeline is over.
    private(set) var roundPosition: ConditioningPosition?
    @ObservationIgnored private(set) var heartRateSearchStartedAt: TimeInterval = 0

    @ObservationIgnored private let workout: any MatSessionWorkoutRecording
    @ObservationIgnored private let checkpoints: WatchMatSessionCheckpointStore?
    @ObservationIgnored private let outbox: WatchMatSessionOutbox?
    /// The round timer's last-used settings (positioning ticket 07); `nil` in tests
    /// that never start a round timer. Internal: `startRoundTimer` lives in `+Rounds.swift`.
    @ObservationIgnored let roundTimerSettings: WatchRoundTimerSettingsStore?
    @ObservationIgnored private let zones: () -> WatchMatIntensityZones?
    @ObservationIgnored private let isOtherWorkoutActive: () -> Bool
    @ObservationIgnored private let play: (WKHapticType) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var clock = ConditioningClock()
    @ObservationIgnored private var externalUUID = UUID()
    @ObservationIgnored private var sessionZones: WatchMatIntensityZones?
    @ObservationIgnored private var tally = MatHeartRateTally()
    @ObservationIgnored private var endedAt: Date?
    @ObservationIgnored private var lastCheckpointElapsed: TimeInterval = 0
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private(set) var roundTimeline: ConditioningTimeline?
    @ObservationIgnored private var lastCueElapsed: TimeInterval = 0

    init(
        workout: any MatSessionWorkoutRecording,
        checkpoints: WatchMatSessionCheckpointStore?,
        outbox: WatchMatSessionOutbox?,
        zones: @escaping () -> WatchMatIntensityZones?,
        isOtherWorkoutActive: @escaping () -> Bool,
        roundTimerSettings: WatchRoundTimerSettingsStore? = nil,
        play: @escaping (WKHapticType) -> Void = { WKInterfaceDevice.current().play($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.workout = workout
        self.checkpoints = checkpoints
        self.outbox = outbox
        self.roundTimerSettings = roundTimerSettings
        self.zones = zones
        self.isOtherWorkoutActive = isOtherWorkoutActive
        self.play = play
        self.now = now
        workout.onHeartRate = { [weak self] bpm in self?.receive(bpm) }
        // Another workout force-ended ours: end here too, as the conditioning runner does.
        workout.onSessionFailed = { [weak self] in self?.end() }
    }

    isolated deinit { tickTask?.cancel() }

    // MARK: - Lifecycle

    func start(_ sport: WatchMatSport) async {
        await begin(sport: sport, rounds: nil)
    }

    /// `rounds` is the round timer's plan (`startRoundTimer`), `nil` for a plain session.
    func begin(sport: WatchMatSport, rounds: RoundTimerConfiguration?) async {
        guard !isActive else { return }
        self.sport = sport
        resetRunState()
        self.rounds = rounds
        roundTimeline = rounds.map { ConditioningTimeline(phases: $0.phases()) }
        roundPosition = roundTimeline?.position(at: 0)
        isRunnerPresented = true
        // The routine list is only reachable with no workout running, but a strength
        // session may still be ending; starting a second session would force-end it.
        guard !isOtherWorkoutActive() else {
            state = .couldNotStart
            return
        }
        let date = now()
        do {
            try await workout.start(sport: sport.rawValue, at: date)
        } catch {
            state = .couldNotStart
            return
        }
        externalUUID = UUID()
        sessionZones = zones()
        clock.start(at: date)
        saveCheckpoint()
        state = .running
        play(.start)
        startTicking()
    }

    /// Continues a session a previous process left running, its HealthKit session
    /// re-adopted (docs/watch-workout-recovery.md) — on the review screen if it had
    /// already been ended.
    func resumeRecovered(from checkpoint: WatchMatSessionCheckpoint) {
        resetRunState()
        sport = checkpoint.sport
        clock = checkpoint.clock
        externalUUID = checkpoint.externalUUID
        sessionZones = checkpoint.zones
        tally = checkpoint.tally
        rounds = checkpoint.rounds
        roundTimeline = checkpoint.rounds.map { ConditioningTimeline(phases: $0.phases()) }
        isRunnerPresented = true
        if let endedAt = checkpoint.endedAt {
            self.endedAt = endedAt
            elapsed = clock.elapsed(at: endedAt)
            enterReview()
            return
        }
        elapsed = clock.elapsed(at: now())
        lastCheckpointElapsed = elapsed
        // No replay of the cues the relaunch missed.
        lastCueElapsed = elapsed
        roundPosition = roundTimeline?.position(at: elapsed)
        heartRateSearchStartedAt = elapsed
        state = clock.isPaused ? .paused : .running
        startTicking()
    }

    func pause() {
        guard state == .running else { return }
        clock.pause(at: now())
        workout.pause()
        saveCheckpoint()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        clock.resume(at: now())
        workout.resume()
        saveCheckpoint()
        state = .running
    }

    /// Stops the clock and opens the review; the Apple Health workout is saved with
    /// the user's intensity in `save()`. Under a minute is discarded outright.
    func end() {
        end(at: now())
    }

    /// `date` is now, or the round timer's last bell — the review shows the
    /// rounds, not the half second the tick took to notice the end.
    private func end(at date: Date) {
        guard state == .running || state == .paused else { return }
        stopTicking()
        elapsed = clock.elapsed(at: date)
        guard elapsed >= Self.minimumDuration else {
            workout.discard()
            checkpoints?.clear()
            state = .finished(.notSaved)
            return
        }
        // Paused, so the session's duration stops at `end` while the user reviews.
        if state == .running { workout.pause() }
        tally.close(at: elapsed, zones: sessionZones)
        // HealthKit excludes the paused stretches itself, so `end` is simply now.
        endedAt = date
        saveCheckpoint()
        play(.stop)
        enterReview()
    }

    /// Saves to Apple Health, then queues the session for the iPhone's History —
    /// whether or not Health saved it — before the checkpoint is cleared.
    func save() async {
        guard case .reviewing = state, let intensity = selectedIntensity,
              let startDate = clock.startDate, let endedAt else { return }
        state = .saving
        let health: HealthOutcome
        do {
            try await workout.finishMatSession(
                at: endedAt,
                externalUUID: externalUUID,
                title: WatchMatSessionCopy.sport(sport)
            )
            health = .saved
        } catch {
            health = .failed
        }
        // The duration excludes pauses, like the Health workout: the record ends at
        // start + session time.
        outbox?.enqueue(WatchCompletedMatSession(
            id: externalUUID,
            startTime: startDate,
            endTime: startDate.addingTimeInterval(elapsed),
            sport: sport.rawValue,
            intensity: intensity.rawValue,
            isSavedToHealth: health == .saved
        ))
        checkpoints?.clear()
        play(.success)
        state = .finished(health)
    }

    /// The review's "Don't save": the timer leaves no trace — no Apple Health
    /// workout, nothing queued for the iPhone.
    func discard() {
        guard case .reviewing = state else { return }
        workout.discard()
        checkpoints?.clear()
        state = .finished(.discarded)
    }

    func dismissRunner() {
        guard !isActive else { return }
        isRunnerPresented = false
    }

    /// The cover's `onDismiss`. A session still open is raised again — it would
    /// otherwise keep running with no way back to it.
    func runnerDidDismiss() {
        if isActive {
            isRunnerPresented = true
        } else {
            state = .idle
        }
    }

    // MARK: - Ticking

    func tick() {
        guard state == .running || state == .paused else { return }
        elapsed = clock.elapsed(at: now())
        if let roundTimeline, let rounds {
            advanceRounds(roundTimeline, warning: rounds.warning)
            guard state == .running || state == .paused else { return }
        }
        if elapsed - lastCheckpointElapsed >= Self.checkpointInterval {
            saveCheckpoint()
        }
    }

    /// A paused clock never advances `elapsed`, so a pause plays no cue.
    private func advanceRounds(_ timeline: ConditioningTimeline, warning: TimeInterval) {
        roundPosition = timeline.position(at: elapsed)
        let cues = ConditioningCueEvaluator.cues(in: timeline, from: lastCueElapsed, to: elapsed, warning: warning)
        lastCueElapsed = elapsed
        for cue in cues {
            if let haptic = Self.haptic(for: cue) { play(haptic) }
        }
        // The last round is over: the timer ends into the review on its own.
        if roundPosition == nil, state == .running {
            end(at: clock.date(forElapsed: timeline.totalDuration, now: now()))
        }
    }

    private func receive(_ bpm: Int) {
        heartRate = bpm
        guard state == .running else { return }
        tally.record(bpm, at: clock.elapsed(at: now()), zones: sessionZones)
    }

    private func enterReview() {
        let suggested = MatIntensitySuggestion.suggest(from: tally, zones: sessionZones)
        selectedIntensity = suggested
        state = .reviewing(Review(
            duration: elapsed,
            averageHeartRate: tally.average,
            maximumHeartRate: tally.maximum,
            suggested: suggested,
            rounds: roundTimeline?.completedWorkIntervals(at: elapsed)
        ))
    }

    private var isActive: Bool {
        switch state {
        case .running, .paused, .reviewing, .saving: true
        default: false
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func resetRunState() {
        clock = ConditioningClock()
        tally = MatHeartRateTally()
        sessionZones = nil
        endedAt = nil
        elapsed = 0
        lastCheckpointElapsed = 0
        heartRateSearchStartedAt = 0
        heartRate = nil
        selectedIntensity = nil
        rounds = nil
        roundTimeline = nil
        roundPosition = nil
        lastCueElapsed = 0
    }

    private func saveCheckpoint() {
        lastCheckpointElapsed = clock.elapsed(at: now())
        checkpoints?.save(WatchMatSessionCheckpoint(
            sport: sport,
            clock: clock,
            externalUUID: externalUUID,
            zones: sessionZones,
            tally: tally,
            endedAt: endedAt,
            rounds: rounds
        ))
    }
}
