//
//  ConditioningTimelineTests.swift
//  GymStreakTests
//
//  The pure timing core of fight conditioning (docs/fight-conditioning.md):
//  phase expansion for intervals, sets with set breaks and steady state, the
//  elapsed→position lookup and the pause-aware wall clock.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct ConditioningTimelineTests {

    private func timeline(
        _ definition: ConditioningSessionDefinition,
        volume: Int,
        subMaximal: Bool = false
    ) -> ConditioningTimeline {
        ConditioningTimeline(plan: ConditioningSessionPlan(
            definition: definition,
            options: ConditioningSessionOptions(volume: volume, isSubMaximal: subMaximal),
            modality: .rower
        ))
    }

    // MARK: - Expansion

    @Test("Intervals: warm-up, work/rest pairs without a trailing rest, cool-down")
    func intervalsExpand() {
        let t = timeline(ConditioningLibrary.lactic30, volume: 6)
        let kinds = t.phases.map(\.kind)

        #expect(kinds.first == .warmUp)
        #expect(kinds.last == .coolDown)
        #expect(kinds.filter { $0 == .work }.count == 6)
        #expect(kinds.filter { $0 == .rest }.count == 5)
        #expect(kinds[kinds.count - 2] == .work)
        let expectedTotal: TimeInterval = 600 + 180 + 600 + 600
        #expect(t.totalDuration == expectedTotal)

        let works = t.phases.filter { $0.kind == .work }
        #expect(works.map(\.round) == [1, 2, 3, 4, 5, 6])
        #expect(works.allSatisfy { $0.roundsPerSet == 6 && $0.set == nil })
        #expect(works.allSatisfy { $0.effort == .hardRepeatable && $0.duration == 30 })
    }

    @Test("Sets: rest between reps, a set break between sets, none after the last set")
    func setsExpandWithSetBreaks() {
        let t = timeline(ConditioningLibrary.alacticPower, volume: 3)
        let kinds = t.phases.map(\.kind)

        #expect(kinds.filter { $0 == .work }.count == 15)
        #expect(kinds.filter { $0 == .rest }.count == 12)
        #expect(kinds.filter { $0 == .setBreak }.count == 2)
        // 15 min warm-up, 15 × 8 s, 12 × 90 s, 2 × 4 min, 5 min cool-down.
        let expectedTotal: TimeInterval = 900 + 120 + 1080 + 480 + 300
        #expect(t.totalDuration == expectedTotal)

        let breaks = t.phases.filter { $0.kind == .setBreak }
        #expect(breaks.map(\.set) == [1, 2])
        #expect(breaks.allSatisfy { $0.duration == 240 })

        let lastWork = t.phases.last { $0.kind == .work }
        #expect(lastWork?.set == 3 && lastWork?.round == 5 && lastWork?.totalSets == 3)
    }

    @Test("Sub-maximal replaces the maximal cue on alactic work only")
    func subMaximalVariant() {
        let t = timeline(ConditioningLibrary.alacticPower, volume: 2, subMaximal: true)
        #expect(t.phases.filter { $0.kind == .work }.allSatisfy { $0.effort == .subMaximal })

        let lactic = timeline(ConditioningLibrary.lactic30, volume: 6, subMaximal: true)
        #expect(lactic.phases.filter { $0.kind == .work }.allSatisfy { $0.effort == .hardRepeatable })
    }

    @Test("Steady state is one block of the chosen minutes")
    func steadyState() {
        let t = timeline(ConditioningLibrary.aerobicBase, volume: 45)
        #expect(t.phases == [ConditioningPhase(kind: .steady, duration: 2700, effort: .conversational)])
        #expect(t.totalDuration == 2700)
        #expect(t.firstEffortOffset == 0)
    }

    // MARK: - Position

    @Test("Position lookup lands in the right phase at boundaries")
    func positionLookup() throws {
        let t = timeline(ConditioningLibrary.lactic30, volume: 6)

        let start = try #require(t.position(at: 0))
        #expect(start.phase.kind == .warmUp && start.remainingInPhase == 600)

        let firstWork = try #require(t.position(at: 600))
        #expect(firstWork.phase.kind == .work && firstWork.phase.round == 1)

        let firstRest = try #require(t.position(at: 630))
        #expect(firstRest.phase.kind == .rest && firstRest.remainingInPhase == 120)

        let secondWork = try #require(t.position(at: 755))
        #expect(secondWork.phase.kind == .work && secondWork.phase.round == 2)
        #expect(secondWork.elapsedInPhase == 5)

        #expect(t.position(at: t.totalDuration) == nil)
    }

    @Test("Effort has begun only after the first work interval starts")
    func hasBegunEffort() {
        let t = timeline(ConditioningLibrary.lactic45, volume: 4)
        #expect(!t.hasBegunEffort(at: 0))
        #expect(!t.hasBegunEffort(at: 600))
        #expect(t.hasBegunEffort(at: 601))
    }

    @Test("Upcoming phase starts are strictly after the given elapsed time")
    func upcomingStarts() {
        let t = timeline(ConditioningLibrary.lactic45, volume: 4)
        let upcoming = t.upcomingPhaseStarts(after: 600)
        #expect(upcoming.first?.offset == 645)
        #expect(upcoming.count == t.phases.count - 2)
    }

    // MARK: - Library

    @Test("Every session id resolves and defaults to its lowest volume")
    func libraryIsComplete() {
        for id in ConditioningSessionDefinition.ID.allCases {
            let session = ConditioningLibrary.session(id)
            #expect(session.defaultVolume == session.volume.options.min())
            #expect(!session.modalities.isEmpty)
        }
        #expect(ConditioningLibrary.sessions.filter(\.supportsSubMaximal).map(\.id) == [.alacticPower])
    }

    // MARK: - Completed work intervals (what History records)

    @Test("Only fully finished work intervals count as completed rounds")
    func completedWorkIntervals() {
        // lactic30: 10 min warm-up, then 6 × 30 s work / 120 s rest, then 10 min cool-down.
        let warmUp: TimeInterval = 10 * 60
        let line = timeline(ConditioningLibrary.lactic30, volume: 6)
        #expect(line.workIntervalCount == 6)

        #expect(line.completedWorkIntervals(at: 0) == 0)
        #expect(line.completedWorkIntervals(at: warmUp) == 0)
        // 20 s into the first round — started, not finished.
        #expect(line.completedWorkIntervals(at: warmUp + 20) == 0)
        #expect(line.completedWorkIntervals(at: warmUp + 30) == 1)
        // First rest done, second round half through.
        #expect(line.completedWorkIntervals(at: warmUp + 30 + 120 + 15) == 1)
        #expect(line.completedWorkIntervals(at: line.totalDuration) == 6)
    }

    @Test("Set-based sessions count every rep of every set as a round")
    func completedWorkIntervalsAcrossSets() {
        let line = timeline(ConditioningLibrary.alacticPower, volume: 2)
        let repsPerSet: Int = switch ConditioningLibrary.alacticPower.volume {
        case .sets(_, let reps): reps
        case .rounds, .minutes: 0
        }
        #expect(line.workIntervalCount == 2 * repsPerSet)
        #expect(line.completedWorkIntervals(at: line.totalDuration) == 2 * repsPerSet)
    }

    @Test("Steady state has no rounds at all")
    func steadyStateHasNoWorkIntervals() {
        let line = timeline(ConditioningLibrary.aerobicBase, volume: 30)
        #expect(line.workIntervalCount == 0)
        #expect(line.completedWorkIntervals(at: line.totalDuration) == 0)
    }

    // MARK: - Clock

    @Test("The clock subtracts paused time and derives from wall-clock dates")
    func clockPauses() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        var clock = ConditioningClock()
        clock.start(at: t0)
        #expect(clock.elapsed(at: t0.addingTimeInterval(30)) == 30)

        clock.pause(at: t0.addingTimeInterval(30))
        #expect(clock.elapsed(at: t0.addingTimeInterval(500)) == 30)

        clock.resume(at: t0.addingTimeInterval(90))
        #expect(clock.elapsed(at: t0.addingTimeInterval(100)) == 40)
        #expect(clock.date(forElapsed: 100, now: t0.addingTimeInterval(100))
                == t0.addingTimeInterval(160))
    }
}
