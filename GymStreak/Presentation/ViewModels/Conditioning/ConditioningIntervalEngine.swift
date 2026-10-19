//
//  ConditioningIntervalEngine.swift
//  GymStreak
//
//  The one interval engine: wall-clock timing over a `ConditioningTimeline`,
//  the in-app cues at its transitions, and the lock-screen notifications for
//  the transitions that fall while the app is suspended. Nothing here counts
//  down — every value is re-derived from `ConditioningClock` + the timeline,
//  so a locked phone resumes at the right place. The conditioning runner and
//  the round timer both own one and supply their vocabulary (which cue plays,
//  what the notifications say); what happens at the end is theirs.
//  See docs/fight-conditioning.md.
//

import Foundation
import Observation

/// What a run knows and the engine does not: the words of the notifications
/// and which live cue each transition plays.
struct ConditioningCueVocabulary {
    struct Text {
        let title: String
        let body: String
    }

    /// Played before a work phase ends, `lead` seconds early — the round
    /// timer's warning. Phases no longer than `lead` get none.
    struct Warning {
        let lead: TimeInterval
        let cue: ConditioningLiveCue
        let text: (ConditioningPhase) -> Text
    }

    /// The live cue when `phase` begins (never called for the first phase).
    let phaseStart: (ConditioningPhase) -> ConditioningLiveCue
    /// Played when the run starts — the round timer's opening bell. A
    /// conditioning session starts into its warm-up silently.
    var startCue: ConditioningLiveCue? = nil
    let finished: ConditioningLiveCue
    let text: (ConditioningPhase) -> Text
    let finishedText: Text
    var warning: Warning?
}

@Observable
@MainActor
final class ConditioningIntervalEngine {

    enum State: Equatable {
        case ready, running, paused, finished
    }

    let timeline: ConditioningTimeline

    private(set) var state: State = .ready
    private(set) var position: ConditioningPosition?
    private(set) var elapsed: TimeInterval = 0
    private(set) var endedEarly = false
    /// Notifications are not allowed, so transition cues only play on screen.
    private(set) var backgroundCuesUnavailable = false

    /// Called once, when the run is over: whether the timeline ran to its end,
    /// and the wall-clock end — the timeline's end when it completed while the
    /// app was suspended, not the moment the app woke up.
    @ObservationIgnored var onFinished: ((_ didComplete: Bool, _ endDate: Date) -> Void)?
    /// Called after every change a Lock Screen mirror has to follow — the
    /// start, each phase boundary, pause, resume and a foreground
    /// resynchronisation. The end has `onFinished`. The round timer's Live
    /// Activity hangs here; the conditioning runner leaves it nil.
    @ObservationIgnored var onTransition: (() -> Void)?

    @ObservationIgnored private var clock = ConditioningClock()
    @ObservationIgnored private var lastPhaseIndex: Int?
    @ObservationIgnored private var lastLeadInSecond: Int?
    @ObservationIgnored private var lastWarningPhaseIndex: Int?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    @ObservationIgnored private let cues: any ConditioningCueDelivering
    @ObservationIgnored private let vocabulary: ConditioningCueVocabulary
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let isTickingAutomatically: Bool

    init(
        timeline: ConditioningTimeline,
        cues: any ConditioningCueDelivering,
        vocabulary: ConditioningCueVocabulary,
        now: @escaping () -> Date = Date.init,
        isTickingAutomatically: Bool = true
    ) {
        self.timeline = timeline
        self.cues = cues
        self.vocabulary = vocabulary
        self.now = now
        self.isTickingAutomatically = isTickingAutomatically
        self.position = timeline.position(at: 0)
    }

    isolated deinit {
        tickTask?.cancel()
    }

    // MARK: - Derived display state

    var startDate: Date? { clock.startDate }
    var pausedAt: Date? { clock.pausedAt }

    /// The wall-clock date at which the run reaches session-relative `offset`,
    /// as the clock stands — frozen at the pause while paused. What a Live
    /// Activity's self-advancing timers are given.
    func date(forElapsed offset: TimeInterval) -> Date {
        clock.date(forElapsed: offset, now: clock.pausedAt ?? now())
    }

    var nextPhase: ConditioningPhase? {
        guard let index = position?.phaseIndex, index + 1 < timeline.phases.count else { return nil }
        return timeline.phases[index + 1]
    }

    var sessionProgress: Double {
        guard timeline.totalDuration > 0 else { return 0 }
        return min(1, elapsed / timeline.totalDuration)
    }

    // MARK: - Controls

    func start() {
        guard state == .ready else { return }
        clock.start(at: now())
        state = .running
        lastPhaseIndex = nil
        refresh()
        if let startCue = vocabulary.startCue { cues.play(startCue) }
        startTicking()
        scheduleBackgroundCues()
        onTransition?()
    }

    func pause() {
        guard state == .running else { return }
        clock.pause(at: now())
        state = .paused
        stopTicking()
        cues.cancelBackgroundCues()
        refresh()
        onTransition?()
    }

    func resume() {
        guard state == .paused else { return }
        clock.resume(at: now())
        state = .running
        refresh()
        startTicking()
        scheduleBackgroundCues()
        onTransition?()
    }

    /// Ends before the timeline did.
    func end() {
        guard state == .running || state == .paused else { return }
        elapsed = clock.elapsed(at: now())
        endedEarly = true
        finish()
    }

    /// Re-derives the display from the clock after returning to the
    /// foreground, without replaying the transitions that happened meanwhile —
    /// their notifications already fired. Reschedules the notifications from
    /// here, so a long run keeps its window of upcoming cues.
    func resynchronize() {
        guard state == .running || state == .paused else { return }
        elapsed = clock.elapsed(at: now())
        position = timeline.position(at: elapsed)
        lastPhaseIndex = position?.phaseIndex
        lastLeadInSecond = nil
        lastWarningPhaseIndex = nil
        if let position, let warning = vocabulary.warning, position.remainingInPhase <= warning.lead {
            lastWarningPhaseIndex = position.phaseIndex
        }
        if position == nil {
            finish()
        } else {
            if state == .running { scheduleBackgroundCues() }
            onTransition?()
        }
    }

    /// One tick: re-derive the position and fire the in-app cues it crossed.
    func refresh() {
        guard state == .running || state == .paused else { return }
        elapsed = clock.elapsed(at: now())
        guard let current = timeline.position(at: elapsed) else {
            finish()
            return
        }
        position = current

        if current.phaseIndex != lastPhaseIndex {
            let isBoundary = lastPhaseIndex != nil
            if isBoundary {
                cues.play(vocabulary.phaseStart(current.phase))
            }
            lastPhaseIndex = current.phaseIndex
            lastLeadInSecond = nil
            if isBoundary { onTransition?() }
        }

        guard state == .running else { return }

        // The warning before a work phase ends, once per phase.
        if let warning = vocabulary.warning,
           current.phase.kind == .work,
           current.phase.duration > warning.lead,
           current.remainingInPhase <= warning.lead,
           lastWarningPhaseIndex != current.phaseIndex {
            lastWarningPhaseIndex = current.phaseIndex
            cues.play(warning.cue)
        }

        // 3-2-1 before every effort phase that follows another phase.
        if let next = nextPhase, next.kind.isEffort {
            let second = Int(current.remainingInPhase.rounded(.up))
            if (1...3).contains(second), second != lastLeadInSecond {
                lastLeadInSecond = second
                cues.play(.leadIn)
            }
        }
    }

    // MARK: - Finish

    private func finish() {
        guard state != .finished else { return }
        let didComplete = !endedEarly
        // A completion noticed late (the app was suspended) still ends when
        // the timeline did, not when the app woke up.
        let endDate = didComplete
            ? clock.date(forElapsed: timeline.totalDuration, now: now())
            : now()
        state = .finished
        stopTicking()
        cues.cancelBackgroundCues()
        if didComplete {
            elapsed = timeline.totalDuration
            cues.play(vocabulary.finished)
        }
        position = nil
        onFinished?(didComplete, endDate)
    }

    // MARK: - Ticking and background cues

    private func startTicking() {
        guard isTickingAutomatically else { return }
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// One notification per upcoming transition — phase starts, warnings and
    /// the end — in time order, so the deliverer's cap keeps the nearest ones.
    private func scheduleBackgroundCues() {
        let current = now()
        let clock = clock
        let elapsed = clock.elapsed(at: current)
        func date(_ offset: TimeInterval) -> Date { clock.date(forElapsed: offset, now: current) }

        var scheduled = timeline.upcomingPhaseStarts(after: elapsed).map { start in
            let phase = timeline.phases[start.index]
            let text = vocabulary.text(phase)
            return ConditioningScheduledCue(
                fireDate: date(start.offset),
                title: text.title,
                body: text.body,
                cue: vocabulary.phaseStart(phase)
            )
        }
        if let warning = vocabulary.warning {
            for offset in timeline.warningOffsets(before: warning.lead) where offset > elapsed {
                guard let phase = timeline.position(at: offset)?.phase else { continue }
                let text = warning.text(phase)
                scheduled.append(ConditioningScheduledCue(
                    fireDate: date(offset), title: text.title, body: text.body, cue: warning.cue
                ))
            }
        }
        scheduled.append(ConditioningScheduledCue(
            fireDate: date(timeline.totalDuration),
            title: vocabulary.finishedText.title,
            body: vocabulary.finishedText.body,
            cue: vocabulary.finished
        ))
        scheduled.sort { $0.fireDate < $1.fireDate }

        Task {
            // A pause or end that landed before this task ran must not be
            // followed by a fresh batch.
            guard state == .running else { return }
            let isAvailable = await cues.scheduleBackgroundCues(scheduled)
            backgroundCuesUnavailable = !isAvailable
        }
    }
}
