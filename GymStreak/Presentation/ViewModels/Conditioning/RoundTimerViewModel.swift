//
//  RoundTimerViewModel.swift
//  GymStreak
//
//  One run of the round timer (docs/fight-conditioning.md, "Round timer"): the
//  shared `ConditioningIntervalEngine` times the rounds and plays the bell;
//  this type adds what a run leaves behind — nothing, unless the user saves it
//  as a mat session, which pre-fills the mat-session form with the preset's
//  sport, the start and the elapsed time — and mirrors the run onto the Lock
//  Screen through the Live Activity presenter at every engine transition. No
//  History record, no Apple Health workout of its own, no Pro surface.
//

import Foundation
import Observation

@Observable
@MainActor
final class RoundTimerViewModel: Identifiable {

    typealias State = ConditioningIntervalEngine.State

    /// Shorter than this is a mis-tap, not a session — the watch's rule too.
    static let minimumSavableDuration: TimeInterval = 60

    /// The run's identity on the Lock Screen: what keys its Live Activity.
    let id = UUID()
    let configuration: RoundTimerConfiguration
    let timeline: ConditioningTimeline
    /// Set once the run was saved as a mat session; a second save is never offered.
    private(set) var hasSavedMatSession = false

    private let engine: ConditioningIntervalEngine
    @ObservationIgnored private let liveActivity: any RoundTimerLiveActivityPresenting
    @ObservationIgnored private let liveActivityRun: RoundTimerLiveActivityContent.Run
    @ObservationIgnored private let makeMatSessionLog: () -> MatSessionLogViewModel

    init(
        configuration: RoundTimerConfiguration,
        cues: any ConditioningCueDelivering,
        liveActivity: any RoundTimerLiveActivityPresenting,
        makeMatSessionLog: @escaping () -> MatSessionLogViewModel,
        now: @escaping () -> Date = Date.init,
        isTickingAutomatically: Bool = true
    ) {
        self.configuration = configuration
        let timeline = ConditioningTimeline(phases: configuration.phases())
        self.timeline = timeline
        self.engine = ConditioningIntervalEngine(
            timeline: timeline,
            cues: cues,
            vocabulary: RoundTimerCopy.vocabulary(for: configuration),
            now: now,
            isTickingAutomatically: isTickingAutomatically
        )
        self.liveActivity = liveActivity
        self.liveActivityRun = RoundTimerCopy.liveActivityRun(for: configuration)
        self.makeMatSessionLog = makeMatSessionLog
        engine.onTransition = { [weak self] in self?.presentLiveActivity() }
        engine.onFinished = { [weak self] didComplete, _ in self?.endLiveActivity(didComplete: didComplete) }
        // The run is created on the Start tap; the opening bell rings a moment
        // later, with the audio session already configured.
        cues.prepareRoundTimer()
    }

    // MARK: - Engine state, as the runner shows it

    var state: State { engine.state }
    var position: ConditioningPosition? { engine.position }
    var elapsed: TimeInterval { engine.elapsed }
    var endedEarly: Bool { engine.endedEarly }
    var backgroundCuesUnavailable: Bool { engine.backgroundCuesUnavailable }
    var nextPhase: ConditioningPhase? { engine.nextPhase }
    var sessionProgress: Double { engine.sessionProgress }

    /// Rounds fully finished so far.
    var completedRounds: Int { timeline.completedWorkIntervals(at: elapsed) }

    /// Inside the last `warning` seconds of a round — the countdown changes colour.
    var isInWarning: Bool {
        guard let position, position.phase.kind == .work, configuration.warning > 0 else { return false }
        return position.remainingInPhase <= configuration.warning
    }

    /// The sport the mat-session form is pre-filled with.
    var matSport: MatSport { MatSport(rawValue: configuration.preset.matSportRawValue) ?? .other }

    var canSaveAsMatSession: Bool {
        state == .finished && !hasSavedMatSession && elapsed >= Self.minimumSavableDuration
    }

    // MARK: - Controls

    func start() { engine.start() }
    func pause() { engine.pause() }
    func resume() { engine.resume() }
    func end() { engine.end() }
    func resynchronize() { engine.resynchronize() }
    func refresh() { engine.refresh() }

    // MARK: - Live Activity

    /// What the Lock Screen shows right now: the whole run between its
    /// wall-clock start and the last bell (always right, the system advances
    /// it), and the current phase, trusted until it ends. `nil` while the run
    /// is not going.
    func liveActivityContent() -> RoundTimerLiveActivityContent? {
        guard state == .running || state == .paused else { return nil }
        let phase = position.map { position in
            let start = engine.date(forElapsed: timeline.startOffsets[position.phaseIndex])
            return RoundTimerLiveActivityContent.Phase(
                label: RoundTimerCopy.phase(position.phase.kind),
                isRound: position.phase.kind == .work,
                position: RoundTimerCopy.position(position.phase),
                range: start...start.addingTimeInterval(position.phase.duration)
            )
        }
        return RoundTimerLiveActivityContent(
            run: liveActivityRun,
            runRange: engine.date(forElapsed: 0)...engine.date(forElapsed: timeline.totalDuration),
            pauseDate: engine.pausedAt,
            phase: phase
        )
    }

    private func presentLiveActivity() {
        guard let content = liveActivityContent() else { return }
        liveActivity.presentActivity(id: id, content: content)
    }

    private func endLiveActivity(didComplete: Bool) {
        liveActivity.endActivity(
            id: id,
            completionMessage: RoundTimerCopy.liveActivityCompletion(
                didComplete: didComplete, rounds: completedRounds, elapsed: elapsed
            )
        )
    }

    // MARK: - Save as mat session

    /// The mat-session form for this run: sport from the preset, the run's
    /// start, and its elapsed time. `nil` while the timer has not run.
    func matSessionLog() -> MatSessionLogViewModel? {
        guard let startDate = engine.startDate, canSaveAsMatSession else { return nil }
        let log = makeMatSessionLog()
        log.prefill(sport: matSport, start: startDate, duration: elapsed)
        return log
    }

    func didSaveMatSession() {
        hasSavedMatSession = true
    }
}
