//
//  WatchConditioningOutboxTests.swift
//  GymStreakWatchTests
//
//  Ticket 07 (docs/fight-conditioning.md): a session finished on the watch is
//  queued for the iPhone's History — durably, once, until acknowledged — with
//  the numbers of the timeline that actually ran, whether or not Apple Health
//  saved it; a session ended in the warm-up queues nothing.
//

import Foundation
import Testing
import WatchKit
@testable import GymStreakWatch_Watch_App

@MainActor
private final class RecordingWorkout: ConditioningWorkoutRecording {
    var onHeartRate: ((Int) -> Void)?
    var onSessionFailed: (() -> Void)?
    var failsToSave = false
    private(set) var externalUUIDs: [UUID] = []

    func start(modality: String, at date: Date) async throws {}
    func pause() {}
    func resume() {}
    func finish(at end: Date, externalUUID: UUID, title: String) async throws {
        externalUUIDs.append(externalUUID)
        if failsToSave { throw CocoaError(.fileWriteUnknown) }
    }
    func discard() {}
}

@Suite @MainActor
struct WatchConditioningOutboxTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// 60 s warm-up, 30 s work, 60 s rest, 30 s work, 60 s cool-down.
    private func intervalSession() -> WatchConditioningSession {
        WatchConditioningSession(
            sessionType: "lactic30", energySystem: "lactic", modalities: ["rower"], volume: 2,
            isSuggestedToday: true,
            phases: [
                ConditioningPhase(kind: .warmUp, duration: 60, effort: .easy),
                ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 1, roundsPerSet: 2),
                ConditioningPhase(kind: .rest, duration: 60, effort: .easy, round: 1, roundsPerSet: 2),
                ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 2, roundsPerSet: 2),
                ConditioningPhase(kind: .coolDown, duration: 60, effort: .easy)
            ],
            heartRateZone: nil
        )
    }

    private func completed(id: UUID = UUID()) -> WatchCompletedConditioningSession {
        WatchCompletedConditioningSession(
            id: id, startTime: start, endTime: start.addingTimeInterval(600), sessionType: "aerobicBase",
            title: "Aerobic base", energySystem: "aerobic", modality: "run", effort: "conversational",
            roundsCompleted: 0, roundsPlanned: 0, setsPlanned: 0, workInterval: 0, restInterval: 0,
            endedEarly: false, isSavedToHealth: true
        )
    }

    private final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    private func makeRunner(
        clock: Clock,
        outbox: WatchConditioningOutbox
    ) -> (WatchConditioningRunViewModel, RecordingWorkout) {
        let workout = RecordingWorkout()
        let runner = WatchConditioningRunViewModel(
            workout: workout,
            checkpoints: nil,
            outbox: outbox,
            isOtherWorkoutActive: { false },
            play: { _ in },
            now: { clock.now }
        )
        return (runner, workout)
    }

    // MARK: - Outbox

    @Test("An entry survives a relaunch and leaves only on the iPhone's ack")
    func persistsUntilAcknowledged() {
        let directory = tempDirectory()
        let entry = completed()
        WatchConditioningOutbox(directory: directory).enqueue(entry)

        let relaunched = WatchConditioningOutbox(directory: directory)
        #expect(relaunched.pending == [entry])

        relaunched.acknowledge(id: UUID())
        #expect(relaunched.pending == [entry])
        relaunched.acknowledge(id: entry.id)
        #expect(relaunched.pending.isEmpty)
        #expect(WatchConditioningOutbox(directory: directory).pending.isEmpty)
    }

    @Test("The same session is queued once, and every enqueue asks for a send")
    func enqueueIsIdempotent() {
        let outbox = WatchConditioningOutbox(directory: tempDirectory())
        var sends = 0
        outbox.onEnqueued = { sends += 1 }
        let entry = completed()
        outbox.enqueue(entry)
        outbox.enqueue(entry)
        #expect(outbox.pending == [entry])
        #expect(sends == 1)
    }

    @Test("The wire payload round-trips and carries the id the watch dedupes transfers on")
    func wireRoundTrip() throws {
        let entry = completed()
        let payload = try #require(WatchConditioningWire.userInfo(for: entry))
        #expect(payload[WatchConditioningWire.completedSessionIdKey] as? String == entry.id.uuidString)
        #expect(WatchConditioningWire.completedSession(from: payload) == entry)
        #expect(WatchConditioningWire.completedSession(from: ["workoutAck": entry.id.uuidString]) == nil)
    }

    // MARK: - Runner → outbox

    @Test("A completed run queues one session with the numbers of the timeline that ran, keyed by the Health id")
    func completedRunIsQueued() async throws {
        let clock = Clock(start)
        let outbox = WatchConditioningOutbox(directory: tempDirectory())
        let (runner, workout) = makeRunner(clock: clock, outbox: outbox)
        await runner.start(intervalSession(), modality: "rower")

        clock.now = start.addingTimeInterval(1_000)
        runner.tick()
        for _ in 0..<200 where outbox.pending.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        let entry = try #require(outbox.pending.first)
        #expect(outbox.pending.count == 1)
        #expect(entry.id == workout.externalUUIDs.first)
        #expect(entry.startTime == start)
        #expect(entry.endTime == start.addingTimeInterval(240))
        #expect(entry.sessionType == "lactic30")
        #expect(entry.modality == "rower")
        #expect(entry.effort == "hardRepeatable")
        #expect(entry.roundsCompleted == 2)
        #expect(entry.roundsPlanned == 2)
        #expect(entry.setsPlanned == 0)
        #expect(entry.workInterval == 30)
        #expect(entry.restInterval == 60)
        #expect(!entry.endedEarly)
        #expect(entry.isSavedToHealth)
    }

    @Test("Ended early after the first round: queued as ended early, only finished rounds count")
    func endedEarlyIsQueued() async throws {
        let clock = Clock(start)
        let outbox = WatchConditioningOutbox(directory: tempDirectory())
        let (runner, _) = makeRunner(clock: clock, outbox: outbox)
        await runner.start(intervalSession(), modality: "rower")
        clock.now = start.addingTimeInterval(160)
        await runner.end()

        let entry = try #require(outbox.pending.first)
        #expect(entry.endedEarly)
        #expect(entry.roundsCompleted == 1)
        #expect(entry.endTime == start.addingTimeInterval(160))
    }

    @Test("A failed Apple Health save still reaches History, marked as not in Health")
    func healthFailureStillQueued() async throws {
        let clock = Clock(start)
        let outbox = WatchConditioningOutbox(directory: tempDirectory())
        let (runner, workout) = makeRunner(clock: clock, outbox: outbox)
        workout.failsToSave = true
        await runner.start(intervalSession(), modality: "rower")
        clock.now = start.addingTimeInterval(100)
        await runner.end()

        let entry = try #require(outbox.pending.first)
        #expect(!entry.isSavedToHealth)
    }

    @Test("Ending during the warm-up queues nothing")
    func warmUpEndQueuesNothing() async {
        let clock = Clock(start)
        let outbox = WatchConditioningOutbox(directory: tempDirectory())
        let (runner, _) = makeRunner(clock: clock, outbox: outbox)
        await runner.start(intervalSession(), modality: "rower")
        clock.now = start.addingTimeInterval(30)
        await runner.end()
        #expect(outbox.pending.isEmpty)
    }

    @Test("Set-based sessions report their sets; the effort is the work phases' (the beginner variant)")
    func setBasedPayload() {
        let phases = [
            ConditioningPhase(kind: .work, duration: 8, effort: .subMaximal, round: 1, roundsPerSet: 1, set: 1, totalSets: 2),
            ConditioningPhase(kind: .setBreak, duration: 240, effort: .easy, set: 1, totalSets: 2),
            ConditioningPhase(kind: .work, duration: 8, effort: .subMaximal, round: 1, roundsPerSet: 1, set: 2, totalSets: 2)
        ]
        let session = WatchConditioningSession(
            sessionType: "alacticPower", energySystem: "alactic", modalities: ["assaultBike"], volume: 2,
            isSuggestedToday: false, phases: phases, heartRateZone: nil
        )
        let entry = WatchCompletedConditioningSession.make(
            id: UUID(), session: session, modality: "assaultBike", title: "Alactic power",
            timeline: ConditioningTimeline(phases: phases), startDate: start, endDate: start.addingTimeInterval(256),
            elapsed: 256, endedEarly: false, isSavedToHealth: true
        )
        #expect(entry.setsPlanned == 2)
        #expect(entry.roundsPlanned == 2)
        #expect(entry.roundsCompleted == 2)
        #expect(entry.restInterval == 0)
        #expect(entry.effort == "subMaximal")
    }
}
