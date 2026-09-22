//
//  WatchConditioningRunViewModel.swift
//  GymStreakWatch Watch App
//
//  Runs one conditioning session on the watch (ticket 06,
//  docs/fight-conditioning.md). Like the iPhone runner it never counts down:
//  every tick re-derives the position from `ConditioningClock` (wall clock
//  minus pauses) and the phases the iPhone synced, so wrist-down, backgrounding
//  or a relaunch cannot drift it. Cues and the zone nudge come from the pure
//  `ConditioningCueEvaluator` / `ConditioningZoneMonitor`.
//

import Foundation
import Observation
import WatchKit

@Observable
@MainActor
final class WatchConditioningRunViewModel {

    enum HealthOutcome: Equatable { case saved, failed, notSaved }

    struct Summary: Equatable {
        let isComplete: Bool
        let elapsed: TimeInterval
        let health: HealthOutcome
    }

    enum State: Equatable {
        case idle
        /// A strength workout's session is still ending; only one session can run.
        case waitingForWorkout
        case couldNotStart
        case running
        case paused
        case finished(Summary)
    }

    private(set) var state: State = .idle
    private(set) var session: WatchConditioningSession?
    private(set) var modality = ""
    private(set) var position: ConditioningPosition?
    private(set) var elapsed: TimeInterval = 0
    private(set) var heartRate: Int?
    var isRunnerPresented = false
    /// Session time at which heart-rate delivery (re)started: 0 on start, the
    /// resume point after crash recovery — where the "no reading yet" window counts from.
    @ObservationIgnored private(set) var heartRateSearchStartedAt: TimeInterval = 0

    @ObservationIgnored private let workout: any ConditioningWorkoutRecording
    @ObservationIgnored private let checkpoints: WatchConditioningCheckpointStore?
    @ObservationIgnored private let isOtherWorkoutActive: () -> Bool
    @ObservationIgnored private let play: (WKHapticType) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var timeline = ConditioningTimeline(phases: [])
    @ObservationIgnored private var clock = ConditioningClock()
    @ObservationIgnored private var externalUUID = UUID()
    @ObservationIgnored private var zoneMonitor = ConditioningZoneMonitor()
    @ObservationIgnored private var lastTickElapsed: TimeInterval = 0
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var isFinishing = false
    /// Chosen on the strength summary; started once that cover is gone.
    @ObservationIgnored private var queued: (session: WatchConditioningSession, modality: String)?

    init(
        workout: any ConditioningWorkoutRecording,
        checkpoints: WatchConditioningCheckpointStore?,
        isOtherWorkoutActive: @escaping () -> Bool,
        play: @escaping (WKHapticType) -> Void = { WKInterfaceDevice.current().play($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.workout = workout
        self.checkpoints = checkpoints
        self.isOtherWorkoutActive = isOtherWorkoutActive
        self.play = play
        self.now = now
        workout.onHeartRate = { [weak self] bpm in self?.heartRate = bpm }
        // Another workout force-ended ours: end the run instead of ticking on without
        // background runtime. The save then reports whatever HealthKit still allows.
        workout.onSessionFailed = { [weak self] in
            Task { await self?.end() }
        }
    }

    isolated deinit { tickTask?.cancel() }

    // MARK: - Derived

    var totalDuration: TimeInterval { timeline.totalDuration }
    var hasBegunEffort: Bool { timeline.hasBegunEffort(at: elapsed) }
    var nextPhase: ConditioningPhase? {
        guard let index = position?.phaseIndex, timeline.phases.indices.contains(index + 1) else { return nil }
        return timeline.phases[index + 1]
    }

    /// The personal range, only while a conversational phase runs; `nil` for RPE-only users.
    var zone: WatchHeartRateZone? {
        guard position?.phase.effort == .conversational else { return nil }
        return session?.heartRateZone
    }

    var zoneStatus: ConditioningZoneStatus? {
        guard let zone, let heartRate else { return nil }
        return ConditioningZoneStatus(heartRate: heartRate, zone: zone)
    }

    // MARK: - Lifecycle

    func start(_ session: WatchConditioningSession, modality: String) async {
        guard state == .idle || isFinishedState else { return }
        self.session = session
        self.modality = modality
        timeline = ConditioningTimeline(phases: session.phases)
        resetRunState()
        isRunnerPresented = true

        // Starting a second session force-ends the first, so a strength workout that
        // is still ending (right after its summary) has to reach `.ended` first.
        state = .waitingForWorkout
        var waited: TimeInterval = 0
        while isOtherWorkoutActive(), waited < 15 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 0.25
        }
        // The user may have backed out while waiting.
        guard isRunnerPresented else {
            state = .idle
            return
        }
        guard !isOtherWorkoutActive() else {
            state = .couldNotStart
            return
        }

        let date = now()
        do {
            try await workout.start(modality: modality, at: date)
        } catch {
            state = .couldNotStart
            return
        }
        externalUUID = UUID()
        clock.start(at: date)
        saveCheckpoint()
        state = .running
        play(.start)
        startTicking()
    }

    /// "Right after a strength workout": the summary queues today's session and
    /// dismisses; the routine list starts it once the workout cover is off screen,
    /// because a cover cannot be presented from under another one.
    func queueAfterWorkout(_ session: WatchConditioningSession) {
        queued = (session, session.modalities.first ?? "")
    }

    func startQueued() async {
        guard let queued else { return }
        self.queued = nil
        await start(queued.session, modality: queued.modality)
    }

    /// Continues a session a previous process left running with its HealthKit
    /// session re-adopted (docs/watch-workout-recovery.md). Cues that fell into
    /// the gap are not replayed.
    func resumeRecovered(from checkpoint: WatchConditioningCheckpoint) {
        session = checkpoint.session
        modality = checkpoint.modality
        timeline = ConditioningTimeline(phases: checkpoint.session.phases)
        resetRunState()
        clock = checkpoint.clock
        externalUUID = checkpoint.externalUUID
        lastTickElapsed = clock.elapsed(at: now())
        heartRateSearchStartedAt = lastTickElapsed
        state = clock.isPaused ? .paused : .running
        isRunnerPresented = true
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
        lastTickElapsed = clock.elapsed(at: now())
        workout.resume()
        saveCheckpoint()
        state = .running
    }

    /// Ends early. Before the first effort phase nothing is saved — the iPhone rule.
    func end() async {
        guard state == .running || state == .paused else { return }
        tick()
        // `tick()` may itself have found the timeline over and claimed the finish.
        guard claimFinish() else { return }
        guard timeline.hasBegunEffort(at: elapsed) else {
            stopTicking()
            workout.discard()
            checkpoints?.clear()
            state = .finished(Summary(isComplete: false, elapsed: elapsed, health: .notSaved))
            return
        }
        await finish(at: now(), isComplete: false)
    }

    func dismissRunner() {
        guard state != .running, state != .paused else { return }
        isRunnerPresented = false
    }

    /// The cover's `onDismiss`, once it is off screen. Resetting here rather than in
    /// `dismissRunner()` keeps the finished screen up for the whole dismiss animation
    /// (the strength cover's empty-screen flash, docs/watch-sync.md). A cover closed
    /// by the system while a session still runs is raised again — otherwise the
    /// session would keep running with no way back to it.
    func runnerDidDismiss() {
        if state == .running || state == .paused {
            isRunnerPresented = true
        } else {
            state = .idle
        }
    }

    // MARK: - Ticking

    func tick() {
        guard state == .running || state == .paused else { return }
        let current = clock.elapsed(at: now())
        for cue in ConditioningCueEvaluator.cues(in: timeline, from: lastTickElapsed, to: current) {
            play(Self.haptic(for: cue))
        }
        lastTickElapsed = current
        elapsed = min(current, timeline.totalDuration)
        position = timeline.position(at: current)
        if let nudge = zoneMonitor.update(zoneStatus, at: current) {
            play(nudge == .below ? .directionUp : .directionDown)
        }
        if position == nil, claimFinish() {
            // The last phase ended — possibly while the process was not running, so
            // the workout ends at the timeline's end, not at wake-up.
            let end = clock.date(forElapsed: timeline.totalDuration, now: now())
            Task { await finish(at: end, isComplete: true) }
        }
    }

    /// Claims the one finish of this run, synchronously — before any suspension
    /// point. Two ticks (the loop and a manual one) can both see the timeline over
    /// before a spawned finish runs; checking a flag *inside* `finish` let the
    /// second one save a second Apple Health workout once the first had completed.
    /// Released only by `resetRunState()` on the next start.
    private func claimFinish() -> Bool {
        guard !isFinishing, state == .running || state == .paused else { return false }
        isFinishing = true
        return true
    }

    /// Callers claim the finish first (`claimFinish()`).
    private func finish(at end: Date, isComplete: Bool) async {
        stopTicking()
        let title = WatchConditioningCopy.title(session?.sessionType ?? "")
        let health: HealthOutcome
        do {
            try await workout.finish(at: end, externalUUID: externalUUID, title: title)
            health = .saved
        } catch {
            health = .failed
        }
        checkpoints?.clear()
        state = .finished(Summary(isComplete: isComplete, elapsed: elapsed, health: health))
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func resetRunState() {
        clock = ConditioningClock()
        zoneMonitor = ConditioningZoneMonitor()
        lastTickElapsed = 0
        heartRateSearchStartedAt = 0
        elapsed = 0
        heartRate = nil
        position = timeline.position(at: 0)
        isFinishing = false
    }

    private var isFinishedState: Bool {
        switch state {
        case .finished, .couldNotStart: true
        default: false
        }
    }

    private func saveCheckpoint() {
        guard let session else { return }
        checkpoints?.save(WatchConditioningCheckpoint(
            session: session,
            modality: modality,
            clock: clock,
            externalUUID: externalUUID
        ))
    }

    static func haptic(for cue: ConditioningRunCue) -> WKHapticType {
        switch cue {
        case .effortStart: .start
        case .recoveryStart: .stop
        case .leadIn: .click
        case .finished: .success
        }
    }
}
