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
    }

    private func makeHarness(
        _ definition: ConditioningSessionDefinition = ConditioningLibrary.lactic30,
        modality: ConditioningModality = .assaultBike
    ) -> Harness {
        let clock = TestClock()
        let cues = RecordingConditioningCues()
        let saver = RecordingConditioningWorkoutSaver()
        let healthSync = StubHealthSyncPreference()
        let viewModel = ConditioningRunViewModel(
            plan: ConditioningSessionPlan(
                definition: definition,
                options: ConditioningSessionOptions(volume: definition.defaultVolume),
                modality: modality
            ),
            cues: cues,
            workoutSaver: saver,
            healthSync: healthSync,
            now: { clock.now },
            isTickingAutomatically: false
        )
        return Harness(viewModel: viewModel, clock: clock, cues: cues, saver: saver, healthSync: healthSync)
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
