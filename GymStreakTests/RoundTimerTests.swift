//
//  RoundTimerTests.swift
//  GymStreakTests
//
//  The round timer (docs/fight-conditioning.md, "Round timer"): preset
//  expansion into the conditioning timeline, the bell / warning / end cues on
//  the shared interval engine, the lock-screen cue batch, "save as mat
//  session" pre-filling exactly one record, and the remembered settings.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoundTimerTests {

    private final class TestClock {
        var now = Date(timeIntervalSinceReferenceDate: 20_000)
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    /// 2 × 30 s rounds, 15 s rest, 10 s warning: round 1 0–30, rest 30–45, round 2 45–75.
    private static let quick = RoundTimerConfiguration(
        preset: .custom, customRoundDuration: 30, customRestDuration: 15, rounds: 2, warning: 10
    )

    private struct Harness {
        let viewModel: RoundTimerViewModel
        let clock: TestClock
        let cues: RecordingConditioningCues
        let repository: SwiftDataMatSessionRepository
        let saver: RecordingMatSessionWorkoutSaver
        let container: ModelContainer
    }

    private func makeHarness(_ configuration: RoundTimerConfiguration = quick) -> Harness {
        let clock = TestClock()
        let cues = RecordingConditioningCues()
        let container = InMemoryModelContainer.make()
        let repository = SwiftDataMatSessionRepository(modelContext: container.mainContext)
        let saver = RecordingMatSessionWorkoutSaver()
        let viewModel = RoundTimerViewModel(
            configuration: configuration,
            cues: cues,
            makeMatSessionLog: {
                MatSessionLogViewModel(
                    sessions: repository,
                    workoutSaver: saver,
                    healthSync: StubHealthSyncPreference(),
                    now: clock.now
                )
            },
            now: { clock.now },
            isTickingAutomatically: false
        )
        return Harness(viewModel: viewModel, clock: clock, cues: cues, repository: repository, saver: saver, container: container)
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: - Configuration → phases

    @Test("Rounds expand to round, rest, round … with no rest after the last round")
    func phasesAlternateWithoutTrailingRest() {
        let phases = RoundTimerConfiguration(
            preset: .boxing, customRoundDuration: 0, customRestDuration: 0, rounds: 3, warning: 10
        ).phases()
        #expect(phases.map(\.kind) == [.work, .rest, .work, .rest, .work])
        #expect(phases.map(\.duration) == [180, 60, 180, 60, 180])
        #expect(phases.map(\.round) == [1, 1, 2, 2, 3])
        #expect(phases.allSatisfy { $0.roundsPerSet == 3 })
    }

    @Test("Presets carry the ticket's lengths and the mat sport they save as")
    func presets() {
        #expect(RoundTimerPreset.bjj.roundDuration == 300 && RoundTimerPreset.bjj.restDuration == 60)
        #expect(RoundTimerPreset.mma.roundDuration == 300 && RoundTimerPreset.mma.restDuration == 60)
        #expect(RoundTimerPreset.boxing.roundDuration == 180 && RoundTimerPreset.boxing.restDuration == 60)
        #expect(RoundTimerPreset.muayThai.roundDuration == 180 && RoundTimerPreset.muayThai.restDuration == 120)
        #expect(RoundTimerPreset.custom.roundDuration == nil)
        #expect(RoundTimerPreset.allCases.map { MatSport(rawValue: $0.matSportRawValue) }
                == [.bjj, .mma, .boxing, .muayThai, .other])
    }

    @Test("A rest of 0 leaves no rest phases; open-ended runs the capped round count with no total")
    func zeroRestAndOpenEnded() {
        let noRest = RoundTimerConfiguration(preset: .custom, customRoundDuration: 60, customRestDuration: 0, rounds: 3, warning: 0)
        #expect(noRest.phases().map(\.kind) == [.work, .work, .work])
        #expect(noRest.totalDuration == 180)

        let open = RoundTimerConfiguration(preset: .bjj, customRoundDuration: 60, customRestDuration: 0, rounds: nil, warning: 10)
        let phases = open.phases()
        #expect(open.isOpenEnded)
        #expect(open.totalDuration == nil)
        #expect(phases.filter { $0.kind == .work }.count == RoundTimerConfiguration.openEndedRoundCount)
        #expect(phases.allSatisfy { $0.roundsPerSet == nil })
    }

    @Test("Warning offsets fall `warning` seconds before each round's end, and never for short rounds")
    func warningOffsets() {
        let timeline = ConditioningTimeline(phases: Self.quick.phases())
        #expect(timeline.warningOffsets(before: 10) == [20, 65])
        #expect(timeline.warningOffsets(before: 0).isEmpty)
        #expect(timeline.warningOffsets(before: 30).isEmpty)
    }

    // MARK: - Cues on the shared engine

    @Test("Opening bell, warning, round-end bell, 3-2-1 lead-in, next bell, final bells")
    func liveCues() {
        let h = makeHarness()
        #expect(h.cues.prepareCount == 1)                          // the bell is loaded before it rings
        h.viewModel.start()
        #expect(h.cues.played == [.roundStart])

        h.clock.advance(19.9); h.viewModel.refresh()
        #expect(h.cues.played.count == 1)
        h.clock.advance(0.1); h.viewModel.refresh()                // 20 s: 10 s left in round 1
        #expect(h.cues.played.last == .roundWarning)
        h.clock.advance(5); h.viewModel.refresh()                  // still inside the window: once only
        #expect(h.cues.played.filter { $0 == .roundWarning }.count == 1)

        h.clock.advance(5); h.viewModel.refresh()                  // 30 s: rest begins
        #expect(h.cues.played.last == .roundEnd)

        for second in [42.5, 43.5, 44.5] {                          // 3-2-1 before round 2
            h.clock.now = Date(timeIntervalSinceReferenceDate: 20_000 + second)
            h.viewModel.refresh()
        }
        #expect(h.cues.played.suffix(3).allSatisfy { $0 == .leadIn })

        h.clock.now = Date(timeIntervalSinceReferenceDate: 20_000 + 45)
        h.viewModel.refresh()
        #expect(h.cues.played.last == .roundStart)
        #expect(h.viewModel.position?.phase.round == 2)

        h.clock.now = Date(timeIntervalSinceReferenceDate: 20_000 + 75)
        h.viewModel.refresh()
        #expect(h.viewModel.state == .finished)
        #expect(h.viewModel.endedEarly == false)
        #expect(h.viewModel.elapsed == 75)
        #expect(h.viewModel.completedRounds == 2)
        #expect(h.cues.played.last == .roundTimerFinished)
    }

    @Test("Lock-screen cues are one per transition and warning, in time order, each with its bell")
    func backgroundCueBatch() async throws {
        let h = makeHarness()
        h.viewModel.start()
        await settle()
        let batch = try #require(h.cues.scheduledBatches.last)
        let start = h.clock.now
        #expect(batch.map { $0.fireDate.timeIntervalSince(start) } == [20, 30, 45, 65, 75])
        #expect(batch.map(\.cue) == [.roundWarning, .roundEnd, .roundStart, .roundWarning, .roundTimerFinished])
        #expect(batch.map(\.fireDate) == batch.map(\.fireDate).sorted())
    }

    @Test("Returning to the foreground reschedules the window and replays no cue")
    func resynchronizeReschedulesSilently() async {
        let h = makeHarness()
        h.viewModel.start()
        await settle()
        let batches = h.cues.scheduledBatches.count
        h.clock.advance(47)                                        // slept through the rest and the bell
        h.viewModel.resynchronize()
        await settle()
        #expect(h.cues.played == [.roundStart])
        #expect(h.viewModel.position?.phase.round == 2)
        #expect(h.cues.scheduledBatches.count == batches + 1)
        #expect(h.cues.scheduledBatches.last?.first?.fireDate == h.clock.now.addingTimeInterval(65 - 47))
    }

    @Test("The warning is not replayed after a resynchronize that lands inside its window")
    func resynchronizeInsideWarningWindow() {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(22)
        h.viewModel.resynchronize()
        h.clock.advance(1)
        h.viewModel.refresh()
        #expect(h.cues.played.filter { $0 == .roundWarning }.isEmpty)
    }

    // MARK: - The end of a run

    @Test("Ending early keeps the rounds done; under a minute there is nothing to save")
    func endEarly() {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(35); h.viewModel.refresh()
        h.viewModel.end()
        #expect(h.viewModel.state == .finished)
        #expect(h.viewModel.endedEarly)
        #expect(h.viewModel.completedRounds == 1)
        #expect(h.viewModel.elapsed == 35)
        #expect(h.viewModel.canSaveAsMatSession == false)
        #expect(h.viewModel.matSessionLog() == nil)
        #expect(h.cues.played.contains(.roundTimerFinished) == false)
    }

    @Test("Save as mat session pre-fills the preset's sport, the start and the elapsed minutes, and writes one record")
    func saveAsMatSession() async throws {
        let boxing = RoundTimerConfiguration(preset: .boxing, customRoundDuration: 0, customRestDuration: 0, rounds: 2, warning: 10)
        let h = makeHarness(boxing)
        let start = h.clock.now
        h.viewModel.start()
        h.clock.advance(420); h.viewModel.refresh()                 // 3:00 + 1:00 + 3:00
        #expect(h.viewModel.state == .finished)
        #expect(h.viewModel.canSaveAsMatSession)

        let log = try #require(h.viewModel.matSessionLog())
        #expect(log.sport == .boxing)
        #expect(log.startDate == start)
        #expect(log.durationMinutes == 7)

        await log.save()
        h.viewModel.didSaveMatSession()
        let sessions = try h.container.mainContext.fetch(FetchDescriptor<MatSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.sport == .boxing)
        #expect(sessions.first?.startTime == start)
        #expect(sessions.first?.endTime == start.addingTimeInterval(420))
        #expect(h.saver.saved.count == 1)
        // Offered once: a second tap cannot create a second record.
        #expect(h.viewModel.canSaveAsMatSession == false)
        #expect(h.viewModel.matSessionLog() == nil)
    }

    @Test("A finished run that is not saved leaves nothing behind; a custom preset saves as 'other'")
    func decliningLeavesNoTrace() throws {
        let h = makeHarness()
        h.viewModel.start()
        h.clock.advance(75); h.viewModel.refresh()
        #expect(h.viewModel.state == .finished)
        #expect(h.viewModel.canSaveAsMatSession)
        #expect(h.viewModel.matSport == .other)
        #expect(try h.container.mainContext.fetch(FetchDescriptor<MatSession>()).isEmpty)
        #expect(h.saver.saved.isEmpty)
    }

    @Test("The pre-filled duration is whole minutes within the form's range")
    func prefillClamps() {
        let log = MatSessionLogViewModel(
            sessions: SwiftDataMatSessionRepository(modelContext: InMemoryModelContainer.make().mainContext),
            workoutSaver: RecordingMatSessionWorkoutSaver(),
            healthSync: StubHealthSyncPreference()
        )
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        log.prefill(sport: .mma, start: start, duration: 90)
        #expect(log.durationMinutes == MatSessionLogViewModel.durationRange.lowerBound)
        log.prefill(sport: .mma, start: start, duration: 23 * 60 + 29)
        #expect(log.durationMinutes == 23)
        #expect(log.startDate == start)
        #expect(log.sport == .mma)
    }

    // MARK: - Settings

    @Test("The last-used configuration round-trips through the store")
    func settingsStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "RoundTimerTests.\(UUID().uuidString)")!
        let store = RoundTimerSettingsStore(defaults: defaults)
        #expect(store.lastUsedConfiguration == nil)
        let configuration = RoundTimerConfiguration(preset: .muayThai, customRoundDuration: 120, customRestDuration: 45, rounds: nil, warning: 15)
        store.remember(configuration)
        #expect(store.lastUsedConfiguration == configuration)
        #expect(RoundTimerSettingsStore(defaults: defaults).lastUsedConfiguration == configuration)
    }

    @Test("Setup opens on the last-used settings, keeps the round count across the open-ended toggle, and remembers on Start")
    func setupViewModel() {
        let defaults = UserDefaults(suiteName: "RoundTimerTests.\(UUID().uuidString)")!
        let store = RoundTimerSettingsStore(defaults: defaults)
        var started: [RoundTimerConfiguration] = []
        let cues = RecordingConditioningCues()
        func makeSetup() -> RoundTimerSetupViewModel {
            RoundTimerSetupViewModel(settings: store) { configuration in
                started.append(configuration)
                return RoundTimerViewModel(
                    configuration: configuration,
                    cues: cues,
                    makeMatSessionLog: { fatalError("not used") },
                    isTickingAutomatically: false
                )
            }
        }

        let setup = makeSetup()
        #expect(setup.configuration == .default)
        setup.select(.boxing)
        setup.rounds = 8
        setup.isOpenEnded = true
        #expect(setup.configuration.rounds == nil)
        setup.isOpenEnded = false
        #expect(setup.configuration.rounds == 8)
        setup.configuration.warning = 5
        setup.start()
        #expect(started.count == 1)
        #expect(setup.activeRun != nil)
        #expect(store.lastUsedConfiguration == setup.configuration)

        let next = makeSetup()
        #expect(next.configuration.preset == .boxing)
        #expect(next.rounds == 8)
        #expect(next.configuration.warning == 5)
    }
}
