//
//  RoundTimerViewModel.swift
//  GymStreak
//
//  One run of the round timer (docs/fight-conditioning.md, "Round timer"): the
//  shared `ConditioningIntervalEngine` times the rounds and plays the bell;
//  this type adds what a run leaves behind — nothing, unless the user saves it
//  as a mat session, which pre-fills the mat-session form with the preset's
//  sport, the start and the elapsed time. No History record, no Apple Health
//  workout of its own, no Pro surface.
//

import Foundation
import Observation

@Observable
@MainActor
final class RoundTimerViewModel: Identifiable {

    typealias State = ConditioningIntervalEngine.State

    /// Shorter than this is a mis-tap, not a session — the watch's rule too.
    static let minimumSavableDuration: TimeInterval = 60

    let configuration: RoundTimerConfiguration
    let timeline: ConditioningTimeline
    /// Set once the run was saved as a mat session; a second save is never offered.
    private(set) var hasSavedMatSession = false

    private let engine: ConditioningIntervalEngine
    @ObservationIgnored private let makeMatSessionLog: () -> MatSessionLogViewModel

    init(
        configuration: RoundTimerConfiguration,
        cues: any ConditioningCueDelivering,
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
        self.makeMatSessionLog = makeMatSessionLog
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
