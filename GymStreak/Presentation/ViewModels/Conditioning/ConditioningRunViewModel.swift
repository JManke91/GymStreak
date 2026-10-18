//
//  ConditioningRunViewModel.swift
//  GymStreak
//
//  Drives one conditioning session: the History record and the Apple Health
//  write at the end of a run the shared `ConditioningIntervalEngine` times and
//  cues. Every displayed value is the engine's, derived from wall-clock dates,
//  never from a decrementing counter, so a locked phone resumes at the right place.
//  See docs/fight-conditioning.md.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConditioningRunViewModel {

    typealias State = ConditioningIntervalEngine.State

    enum HealthSaveOutcome: Equatable {
        /// Ended before the first effort, Health sync is off, or Health is unavailable.
        case notSaved
        case saving
        case saved
        case failed
    }

    let plan: ConditioningSessionPlan
    let timeline: ConditioningTimeline

    private(set) var healthSaveOutcome: HealthSaveOutcome = .notSaved
    /// The record this run wrote to History, once it has one.
    private(set) var recordedSessionId: UUID?

    private let engine: ConditioningIntervalEngine
    @ObservationIgnored private let workoutSaver: any ConditioningWorkoutSaving
    @ObservationIgnored private let healthSync: any HealthSyncPreferenceReading
    @ObservationIgnored private let records: any ConditioningRecordRepository
    /// Snapshot taken when the session is created; edits mid-session do not apply.
    @ObservationIgnored private let heartRateProfile: HeartRateProfile?

    init(
        plan: ConditioningSessionPlan,
        cues: any ConditioningCueDelivering,
        workoutSaver: any ConditioningWorkoutSaving,
        healthSync: any HealthSyncPreferenceReading,
        records: any ConditioningRecordRepository,
        heartRateProfile: HeartRateProfile? = nil,
        now: @escaping () -> Date = Date.init,
        isTickingAutomatically: Bool = true
    ) {
        self.plan = plan
        let timeline = ConditioningTimeline(plan: plan)
        self.timeline = timeline
        self.engine = ConditioningIntervalEngine(
            timeline: timeline,
            cues: cues,
            vocabulary: Self.vocabulary,
            now: now,
            isTickingAutomatically: isTickingAutomatically
        )
        self.workoutSaver = workoutSaver
        self.healthSync = healthSync
        self.records = records
        self.heartRateProfile = heartRateProfile
        engine.onFinished = { [weak self] didComplete, endDate in
            self?.didFinish(didComplete: didComplete, endDate: endDate)
        }
    }

    // MARK: - Engine state, as the runner shows it

    var state: State { engine.state }
    var position: ConditioningPosition? { engine.position }
    var elapsed: TimeInterval { engine.elapsed }
    var endedEarly: Bool { engine.endedEarly }
    /// Notifications are not allowed, so transition cues only play on screen.
    var backgroundCuesUnavailable: Bool { engine.backgroundCuesUnavailable }
    var nextPhase: ConditioningPhase? { engine.nextPhase }
    var sessionProgress: Double { engine.sessionProgress }

    var sessionTitle: String { ConditioningCopy.title(plan.definition.id) }

    /// The personal heart-rate range for `phase`, if its effort has one.
    func heartRateTarget(for phase: ConditioningPhase) -> HeartRateTarget? {
        HeartRateZones.target(for: phase.effort, profile: heartRateProfile)
    }

    // MARK: - Controls

    func start() {
        guard state == .ready else { return }
        engine.start()
        if healthSync.isHealthSyncEnabled, workoutSaver.isHealthKitAvailable {
            Task { await workoutSaver.prepareConditioningAuthorization() }
        }
    }

    func pause() { engine.pause() }
    func resume() { engine.resume() }

    /// Ends before the timeline did. Records only when the first effort phase
    /// has begun — stopping during the warm-up leaves nothing in History or Health.
    func end() { engine.end() }

    /// After returning to the foreground: jumps to the current phase without
    /// replaying the cues that happened meanwhile.
    func resynchronize() { engine.resynchronize() }

    /// One tick: re-derive the position and fire the in-app cues it crossed.
    func refresh() { engine.refresh() }

    // MARK: - Finish

    private func didFinish(didComplete: Bool, endDate: Date) {
        // Same threshold as the Health write: a session abandoned during the warm-up
        // never began, so it leaves nothing behind anywhere.
        guard let startDate = engine.startDate, timeline.hasBegunEffort(at: elapsed) else { return }

        let record = log(startDate: startDate, endDate: endDate)
        recordedSessionId = record?.id

        guard let record, healthSync.isHealthSyncEnabled, workoutSaver.isHealthKitAvailable
        else { return }

        healthSaveOutcome = .saving
        let externalUUID = record.id
        let plan = plan
        let title = sessionTitle
        Task {
            do {
                try await workoutSaver.saveConditioningWorkout(
                    externalUUID: externalUUID,
                    modality: plan.modality,
                    startDate: startDate,
                    endDate: endDate,
                    title: title
                )
                // Re-resolved rather than captured: the record is a main-context `@Model`
                // and the user may have deleted it from History while the write was in flight.
                records.find(id: externalUUID)?.healthKitWorkoutId = externalUUID
                try? records.save()
                healthSaveOutcome = .saved
            } catch {
                print("Conditioning Health save failed: \(error)")
                healthSaveOutcome = .failed
            }
        }
    }

    /// Writes the History record. It is created *before* the Apple Health write and never
    /// depends on it: GymStreak is the source of truth, and a user with Health sync off
    /// still gets their session logged (docs/fight-conditioning.md).
    private func log(startDate: Date, endDate: Date) -> ConditioningRecord? {
        let record = ConditioningRecord.make(
            id: UUID(),
            plan: plan,
            timeline: timeline,
            title: sessionTitle,
            startDate: startDate,
            endDate: endDate,
            elapsed: elapsed,
            endedEarly: endedEarly
        )
        records.insert(record)
        do {
            try records.save()
        } catch {
            print("Conditioning record save failed: \(error)")
            return nil
        }
        NotificationCenter.default.post(name: .historySourceDataDidChange, object: nil)
        return record
    }

    // MARK: - Cue vocabulary

    /// Effort vs. recovery cues, and notifications that name the phase, the
    /// position and the effort.
    private static let vocabulary = ConditioningCueVocabulary(
        phaseStart: { $0.kind.isEffort ? .effortStart : .recoveryStart },
        finished: .finished,
        text: { phase in
            let detail = [ConditioningCopy.position(phase), ConditioningCopy.effort(phase.effort)]
                .compactMap { $0 }
                .joined(separator: " · ")
            return .init(title: ConditioningCopy.phase(phase.kind), body: detail)
        },
        finishedText: .init(
            title: "conditioning.notification.finished.title".localized,
            body: "conditioning.notification.finished.body".localized
        ),
        warning: nil
    )
}

/// Presented with `fullScreenCover(item:)`; identity is the instance.
extension ConditioningRunViewModel: Identifiable {}
