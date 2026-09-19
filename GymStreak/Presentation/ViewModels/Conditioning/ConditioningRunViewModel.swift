//
//  ConditioningRunViewModel.swift
//  GymStreak
//
//  Drives one conditioning session: wall-clock timing, transition cues and the
//  Apple Health write at the end. Every displayed value is derived from
//  `ConditioningClock` + `ConditioningTimeline`, never from a decrementing
//  counter, so a locked phone resumes at the right place.
//  See docs/fight-conditioning.md.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConditioningRunViewModel {

    enum State: Equatable {
        case ready, running, paused, finished
    }

    enum HealthSaveOutcome: Equatable {
        /// Ended before the first effort, Health sync is off, or Health is unavailable.
        case notSaved
        case saving
        case saved
        case failed
    }

    let plan: ConditioningSessionPlan
    let timeline: ConditioningTimeline

    private(set) var state: State = .ready
    private(set) var position: ConditioningPosition?
    private(set) var elapsed: TimeInterval = 0
    private(set) var endedEarly = false
    private(set) var healthSaveOutcome: HealthSaveOutcome = .notSaved
    /// Notifications are not allowed, so transition cues only play on screen.
    private(set) var backgroundCuesUnavailable = false

    @ObservationIgnored private var clock = ConditioningClock()
    @ObservationIgnored private var lastPhaseIndex: Int?
    @ObservationIgnored private var lastLeadInSecond: Int?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    @ObservationIgnored private let cues: any ConditioningCueDelivering
    @ObservationIgnored private let workoutSaver: any ConditioningWorkoutSaving
    @ObservationIgnored private let healthSync: any HealthSyncPreferenceReading
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let isTickingAutomatically: Bool

    init(
        plan: ConditioningSessionPlan,
        cues: any ConditioningCueDelivering,
        workoutSaver: any ConditioningWorkoutSaving,
        healthSync: any HealthSyncPreferenceReading,
        now: @escaping () -> Date = Date.init,
        isTickingAutomatically: Bool = true
    ) {
        self.plan = plan
        self.timeline = ConditioningTimeline(plan: plan)
        self.cues = cues
        self.workoutSaver = workoutSaver
        self.healthSync = healthSync
        self.now = now
        self.isTickingAutomatically = isTickingAutomatically
        self.position = timeline.position(at: 0)
    }

    isolated deinit {
        tickTask?.cancel()
    }

    // MARK: - Derived display state

    var nextPhase: ConditioningPhase? {
        guard let index = position?.phaseIndex, index + 1 < timeline.phases.count else { return nil }
        return timeline.phases[index + 1]
    }

    var sessionProgress: Double {
        guard timeline.totalDuration > 0 else { return 0 }
        return min(1, elapsed / timeline.totalDuration)
    }

    var sessionTitle: String { ConditioningCopy.title(plan.definition.id) }

    // MARK: - Controls

    func start() {
        guard state == .ready else { return }
        clock.start(at: now())
        state = .running
        lastPhaseIndex = nil
        refresh()
        startTicking()
        scheduleBackgroundCues()
        if healthSync.isHealthSyncEnabled, workoutSaver.isHealthKitAvailable {
            Task { await workoutSaver.prepareConditioningAuthorization() }
        }
    }

    func pause() {
        guard state == .running else { return }
        clock.pause(at: now())
        state = .paused
        stopTicking()
        cues.cancelBackgroundCues()
        refresh()
    }

    func resume() {
        guard state == .paused else { return }
        clock.resume(at: now())
        state = .running
        refresh()
        startTicking()
        scheduleBackgroundCues()
    }

    /// Ends before the timeline did. Saves only when the first effort phase
    /// has begun — stopping during the warm-up leaves nothing in Health.
    func end() {
        guard state == .running || state == .paused else { return }
        elapsed = clock.elapsed(at: now())
        endedEarly = true
        finish()
    }

    /// Re-derives the display from the clock after returning to the
    /// foreground, without replaying the transitions that happened meanwhile —
    /// their notifications already fired.
    func resynchronize() {
        guard state == .running || state == .paused else { return }
        elapsed = clock.elapsed(at: now())
        position = timeline.position(at: elapsed)
        lastPhaseIndex = position?.phaseIndex
        lastLeadInSecond = nil
        if position == nil { finish() }
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
            if lastPhaseIndex != nil {
                cues.play(current.phase.kind.isEffort ? .effortStart : .recoveryStart)
            }
            lastPhaseIndex = current.phaseIndex
            lastLeadInSecond = nil
        }

        // 3-2-1 before every effort phase that follows another phase.
        if state == .running, let next = nextPhase, next.kind.isEffort {
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
        // A completion noticed late (the app was suspended) still ends the
        // Health workout when the timeline did, not when the app woke up.
        let endDate = didComplete
            ? clock.date(forElapsed: timeline.totalDuration, now: now())
            : now()
        state = .finished
        stopTicking()
        cues.cancelBackgroundCues()
        if didComplete {
            elapsed = timeline.totalDuration
            cues.play(.finished)
        }
        position = nil

        guard let startDate = clock.startDate,
              timeline.hasBegunEffort(at: elapsed),
              healthSync.isHealthSyncEnabled,
              workoutSaver.isHealthKitAvailable
        else { return }

        healthSaveOutcome = .saving
        let plan = plan
        let title = sessionTitle
        Task {
            do {
                try await workoutSaver.saveConditioningWorkout(
                    modality: plan.modality,
                    startDate: startDate,
                    endDate: endDate,
                    title: title
                )
                healthSaveOutcome = .saved
            } catch {
                print("Conditioning Health save failed: \(error)")
                healthSaveOutcome = .failed
            }
        }
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

    private func scheduleBackgroundCues() {
        let current = now()
        let clock = clock
        var scheduled = timeline.upcomingPhaseStarts(after: clock.elapsed(at: current)).map { start in
            let phase = timeline.phases[start.index]
            let detail = [ConditioningCopy.position(phase), ConditioningCopy.effort(phase.effort)]
                .compactMap { $0 }
                .joined(separator: " · ")
            return ConditioningScheduledCue(
                fireDate: clock.date(forElapsed: start.offset, now: current),
                title: ConditioningCopy.phase(phase.kind),
                body: detail
            )
        }
        scheduled.append(ConditioningScheduledCue(
            fireDate: clock.date(forElapsed: timeline.totalDuration, now: current),
            title: "conditioning.notification.finished.title".localized,
            body: "conditioning.notification.finished.body".localized
        ))
        Task {
            // A pause or end that landed before this task ran must not be
            // followed by a fresh batch.
            guard state == .running else { return }
            let isAvailable = await cues.scheduleBackgroundCues(scheduled)
            backgroundCuesUnavailable = !isAvailable
        }
    }
}

/// Presented with `fullScreenCover(item:)`; identity is the instance.
extension ConditioningRunViewModel: Identifiable {}
