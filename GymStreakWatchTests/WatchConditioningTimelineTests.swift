//
//  WatchConditioningTimelineTests.swift
//  GymStreakWatchTests
//
//  Ticket 06 (docs/fight-conditioning.md): the watch runs the phases the
//  iPhone expanded, with its OWN copy of the timing engine and the wire
//  model. These tests cover the watch copies, and the drift guard fails the
//  moment a shared file differs between the two targets.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchConditioningTimelineTests {

    /// 60 s warm-up, 2 × (30 s work, 120 s rest) without a trailing rest, 60 s cool-down.
    private let phases: [ConditioningPhase] = [
        ConditioningPhase(kind: .warmUp, duration: 60, effort: .easy),
        ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 1, roundsPerSet: 2),
        ConditioningPhase(kind: .rest, duration: 120, effort: .easy, round: 1, roundsPerSet: 2),
        ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 2, roundsPerSet: 2),
        ConditioningPhase(kind: .coolDown, duration: 60, effort: .easy)
    ]

    @Test("Offsets, total and the elapsed → position lookup")
    func positionLookup() throws {
        let timeline = ConditioningTimeline(phases: phases)
        #expect(timeline.startOffsets == [0, 60, 90, 210, 240])
        #expect(timeline.totalDuration == 300)
        let inRest = try #require(timeline.position(at: 100))
        #expect(inRest.phase.kind == .rest)
        #expect(inRest.remainingInPhase == 110)
        #expect(timeline.position(at: 300) == nil)
    }

    @Test("Nothing counts before the first effort; a round counts once it is finished")
    func effortAndRounds() {
        let timeline = ConditioningTimeline(phases: phases)
        #expect(!timeline.hasBegunEffort(at: 60))
        #expect(timeline.hasBegunEffort(at: 61))
        #expect(timeline.completedWorkIntervals(at: 89) == 0)
        #expect(timeline.completedWorkIntervals(at: 90) == 1)
    }

    @Test("The clock subtracts pauses and survives a checkpoint round trip")
    func pauseAwareClock() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = ConditioningClock()
        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(100))
        #expect(clock.elapsed(at: start.addingTimeInterval(500)) == 100)
        clock.resume(at: start.addingTimeInterval(160))
        #expect(clock.elapsed(at: start.addingTimeInterval(200)) == 140)

        let decoded = try JSONDecoder().decode(ConditioningClock.self, from: JSONEncoder().encode(clock))
        #expect(decoded == clock)
    }

    @Test("Shared files are identical in both targets", arguments: [
        ("GymStreak/Domain/Models/Conditioning/ConditioningPhase.swift",
         "GymStreakWatch Watch App/Models/Conditioning/ConditioningPhase.swift"),
        ("GymStreak/Domain/Services/ConditioningTimeline.swift",
         "GymStreakWatch Watch App/Models/Conditioning/ConditioningTimeline.swift"),
        ("GymStreak/Data/Sync/WatchConditioningModels.swift",
         "GymStreakWatch Watch App/Models/WatchConditioningModels.swift")
    ])
    func sharedCopiesMatch(iOS: String, watch: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let iOSCopy = try String(contentsOf: root.appendingPathComponent(iOS), encoding: .utf8)
        let watchCopy = try String(contentsOf: root.appendingPathComponent(watch), encoding: .utf8)
        #expect(iOSCopy == watchCopy, "\(watch) drifted from its iOS twin")
    }
}
