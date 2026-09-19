//
//  ConditioningRunViewModelTests.swift
//  GymStreakTests
//
//  The conditioning runner (docs/fight-conditioning.md): wall-clock resume,
//  transition + lead-in cues, and the Apple Health save rules — one workout of
//  the plan's modality on finish, nothing when ended before the first effort,
//  nothing when Health sync is off.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ConditioningRunViewModelTests {

    private final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 10_000)
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    private struct Harness {
        let viewModel: ConditioningRunViewModel
        let clock: TestClock
        let cues: RecordingConditioningCues
        let saver: RecordingConditioningWorkoutSaver
        let healthSync: StubHealthSyncPreference
        let records: RecordingConditioningRecordRepository
    }

    private func makeHarness(
        _ definition: ConditioningSessionDefinition = ConditioningLibrary.lactic30,
        modality: ConditioningModality = .assaultBike
    ) -> Harness {
        let clock = TestClock()
        let cues = RecordingConditioningCues()
        let saver = RecordingConditioningWorkoutSaver()
        let healthSync = StubHealthSyncPreference()
        let records = RecordingConditioningRecordRepository()
        let viewModel = ConditioningRunViewModel(
            plan: ConditioningSessionPlan(
                definition: definition,
                options: ConditioningSessionOptions(volume: definition.defaultVolume),
                modality: modality
            ),
            cues: cues,
            workoutSaver: saver,
            healthSync: healthSync,
            records: records,
            now: { clock.now },
            isTickingAutomatically: false
        )
        return Harness(
            viewModel: viewModel,
            clock: clock,
            cues: cues,
            saver: saver,
            healthSync: healthSync,
            records: records
        )
    }

    /// Lets the view model's fire-and-forget save/schedule tasks run.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test("Finishing saves exactly one workout with the plan's modality and the timeline's end")
    func finishSavesOnce() async {
        let h = makeHarness()
        let start = h.clock.now
        h.viewModel.start()

        h.clock.advance(h.viewModel.timeline.totalDuration + 120) // noticed late
        h.viewModel.refresh()
        await settle()

        #expect(h.viewModel.state == .finished)
        #expect(h.saver.saved.count == 1)
        #expect(h.saver.saved.first?.modality == .assaultBike)
        #expect(h.saver.saved.first?.startDate == start)
        #expect(h.saver.saved.first?.endDate == start.addingTimeInterval(h.viewModel.timeline.totalDuration))
        #expect(h.viewModel.healthSaveOutcome == .saved)
        #expect(h.cues.played.last == .finished)
    }

    @Test("Ending during the warm-up saves nothing")
    func endBeforeFirstEffortSavesNothing() async {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(300)
        h.viewModel.end()
        await settle()

        #expect(h.viewModel.state == .finished)
        #expect(h.viewModel.endedEarly)
        #expect(h.saver.saved.isEmpty)
        #expect(h.viewModel.healthSaveOutcome == .notSaved)
    }

    @Test("Ending after the first work interval began saves up to now")
    func endAfterFirstEffortSaves() async {
        let h = makeHarness()
        let start = h.clock.now
        h.viewModel.start()
        h.clock.advance(700)
        h.viewModel.end()
        await settle()

        #expect(h.saver.saved.count == 1)
        #expect(h.saver.saved.first?.endDate == start.addingTimeInterval(700))
    }

    @Test("Health sync off: finishing saves nothing")
    func healthSyncOffSavesNothing() async {
        let h = makeHarness()
        h.healthSync.isHealthSyncEnabled = false
        h.viewModel.start()
        h.clock.advance(h.viewModel.timeline.totalDuration)
        h.viewModel.refresh()
        await settle()

        #expect(h.saver.saved.isEmpty)
    }

    // MARK: - History record (docs/fight-conditioning.md, ticket 02)

    @Test("Finishing records exactly one session, and its id is the Health external UUID")
    func finishRecordsOnce() async throws {
        let h = makeHarness()
        let start = h.clock.now
        h.viewModel.start()

        h.clock.advance(h.viewModel.timeline.totalDuration)
        h.viewModel.refresh()
        await settle()

        #expect(h.records.records.count == 1)
        let record = try #require(h.records.records.first)
        #expect(record.startTime == start)
        #expect(record.endTime == start.addingTimeInterval(h.viewModel.timeline.totalDuration))
        #expect(record.sessionType == .lactic30)
        #expect(record.energySystem == .lactic)
        #expect(record.modality == .assaultBike)
        #expect(record.effort == .hardRepeatable)
        #expect(record.roundsCompleted == 6)
        #expect(record.roundsPlanned == 6)
        #expect(record.workInterval == 30)
        #expect(record.restInterval == 120)
        #expect(record.endedEarly == false)
        // The Health workout is stamped with the record's own id, and the record
        // is updated once the write lands.
        #expect(h.saver.saved.first?.externalUUID == record.id)
        #expect(record.healthKitWorkoutId == record.id)
        #expect(h.viewModel.recordedSessionId == record.id)
    }

    @Test("Ending during the warm-up records nothing")
    func endBeforeFirstEffortRecordsNothing() async {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(300)
        h.viewModel.end()
        await settle()

        #expect(h.records.records.isEmpty)
        #expect(h.viewModel.recordedSessionId == nil)
    }

    @Test("Ending early records the rounds actually finished")
    func endEarlyRecordsCompletedRounds() async throws {
        let h = makeHarness()
        h.viewModel.start()
        // 10 min warm-up, then two full 30 s rounds with a 120 s rest between them,
        // stopped 10 s into the third.
        h.clock.advance(600 + 30 + 120 + 30 + 120 + 10)
        h.viewModel.end()
        await settle()

        let record = try #require(h.records.records.first)
        #expect(record.roundsCompleted == 2)
        #expect(record.roundsPlanned == 6)
        #expect(record.endedEarly == true)
    }

    /// GymStreak is the source of truth: History must not depend on Apple Health.
    @Test("Health sync off still records the session")
    func healthSyncOffStillRecords() async {
        let h = makeHarness()
        h.healthSync.isHealthSyncEnabled = false
        h.viewModel.start()
        h.clock.advance(h.viewModel.timeline.totalDuration)
        h.viewModel.refresh()
        await settle()

        #expect(h.saver.saved.isEmpty)
        #expect(h.records.records.count == 1)
        #expect(h.records.records.first?.healthKitWorkoutId == nil, "nothing was written to Health")
    }

    @Test("A failed Health write leaves the record in place, without a Health id")
    func failedHealthWriteKeepsTheRecord() async {
        struct Boom: Error {}
        let h = makeHarness()
        h.saver.saveError = Boom()
        h.viewModel.start()
        h.clock.advance(h.viewModel.timeline.totalDuration)
        h.viewModel.refresh()
        await settle()

        #expect(h.viewModel.healthSaveOutcome == .failed)
        #expect(h.records.records.count == 1)
        #expect(h.records.records.first?.healthKitWorkoutId == nil)
    }

    /// The runner screen calls `end()` from `onDisappear`, which must not add a second row
    /// after the timeline already finished the session.
    @Test("Ending after the session already finished does not record a second session")
    func endAfterFinishDoesNotDoubleRecord() async {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(h.viewModel.timeline.totalDuration)
        h.viewModel.refresh()
        await settle()

        h.viewModel.end()
        await settle()

        #expect(h.records.records.count == 1)
        #expect(h.saver.saved.count == 1)
    }

    @Test("A steady-state session records no rounds")
    func steadyStateRecordsNoRounds() async throws {
        let h = makeHarness(ConditioningLibrary.aerobicBase, modality: .run)
        h.viewModel.start()
        h.clock.advance(h.viewModel.timeline.totalDuration)
        h.viewModel.refresh()
        await settle()

        let record = try #require(h.records.records.first)
        #expect(record.isSteadyState == true)
        #expect(record.roundsPlanned == 0)
        #expect(record.roundsCompleted == 0)
        #expect(record.workInterval == 0)
    }

    @Test("The beginner variant is recorded as the sub-maximal effort")
    func subMaximalVariantIsRecorded() async throws {
        let clock = TestClock()
        let records = RecordingConditioningRecordRepository()
        let definition = ConditioningLibrary.alacticPower
        let viewModel = ConditioningRunViewModel(
            plan: ConditioningSessionPlan(
                definition: definition,
                options: ConditioningSessionOptions(volume: 2, isSubMaximal: true),
                modality: .rower
            ),
            cues: RecordingConditioningCues(),
            workoutSaver: RecordingConditioningWorkoutSaver(),
            healthSync: StubHealthSyncPreference(),
            records: records,
            now: { clock.now },
            isTickingAutomatically: false
        )
        viewModel.start()
        clock.advance(viewModel.timeline.totalDuration)
        viewModel.refresh()
        await settle()

        let record = try #require(records.records.first)
        #expect(record.effort == .subMaximal)
        #expect(record.setsPlanned == 2)
        #expect(record.roundsPlanned == 10)
    }

    @Test("Pause freezes the countdown and cancels background cues; resume reschedules")
    func pauseAndResume() async {
        let h = makeHarness()
        h.viewModel.start()
        await settle()
        h.clock.advance(100)
        h.viewModel.pause()
        let cancelsAfterPause = h.cues.cancelCount

        h.clock.advance(1_000)
        h.viewModel.refresh()
        #expect(h.viewModel.elapsed == 100)
        #expect(h.viewModel.position?.remainingInPhase == 500)
        #expect(cancelsAfterPause >= 1)

        h.viewModel.resume()
        await settle()
        #expect(h.cues.scheduledBatches.count == 2)
        // Rescheduled cues fire relative to the resumed clock: first work at
        // elapsed 600 is 500 s from now.
        #expect(h.cues.scheduledBatches.last?.first?.fireDate == h.clock.now.addingTimeInterval(500))
    }

    @Test("A resynchronize after backgrounding jumps ahead without replaying cues")
    func resynchronizeSkipsMissedCues() {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(760) // warm-up, work 1, rest 1 passed while locked
        h.viewModel.resynchronize()

        #expect(h.viewModel.position?.phase.kind == .work)
        #expect(h.viewModel.position?.phase.round == 2)
        #expect(h.cues.played.isEmpty)
    }

    @Test("A 3-2-1 lead-in plays before a work interval, then the transition cue")
    func leadInThenTransition() {
        let h = makeHarness()
        h.viewModel.start()
        for elapsed in stride(from: 596.5, through: 600.5, by: 0.5) {
            h.clock.now = Date(timeIntervalSinceReferenceDate: 10_000 + elapsed)
            h.viewModel.refresh()
        }
        #expect(h.cues.played == [.leadIn, .leadIn, .leadIn, .effortStart])
    }
}
