//
//  WatchConditioningRunCuesTests.swift
//  GymStreakWatchTests
//
//  Ticket 06 (docs/fight-conditioning.md): which haptic a runner tick plays,
//  and when the heart-rate zone nudge fires.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchConditioningRunCuesTests {

    private let timeline = ConditioningTimeline(phases: [
        ConditioningPhase(kind: .warmUp, duration: 60, effort: .easy),
        ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 1, roundsPerSet: 2),
        ConditioningPhase(kind: .rest, duration: 120, effort: .easy, round: 1, roundsPerSet: 2),
        ConditioningPhase(kind: .work, duration: 30, effort: .hardRepeatable, round: 2, roundsPerSet: 2)
    ])

    private func cues(_ from: TimeInterval, _ to: TimeInterval) -> [ConditioningRunCue] {
        ConditioningCueEvaluator.cues(in: timeline, from: from, to: to)
    }

    @Test("3-2-1 before an effort phase, then the effort cue at its start")
    func leadInAndEffortStart() {
        #expect(cues(56.9, 57.1) == [.leadIn(3)])
        #expect(cues(58.9, 59.1) == [.leadIn(1)])
        #expect(cues(59.9, 60.1) == [.effortStart])
    }

    @Test("A recovery phase gets its own cue; the last phase ending plays finished")
    func recoveryAndFinish() {
        #expect(cues(89.9, 90.1) == [.recoveryStart])
        #expect(cues(239.9, 240.1) == [.finished])
    }

    @Test("A catch-up jump replays nothing, and a paused clock produces nothing")
    func noReplay() {
        #expect(cues(10, 100).isEmpty)
        #expect(cues(60.5, 60.5).isEmpty)
    }

    @Test("Zone status against the personal range")
    func zoneStatus() {
        let zone = WatchHeartRateZone(lowerBPM: 120, upperBPM: 145)
        #expect(ConditioningZoneStatus(heartRate: 119, zone: zone) == .below)
        #expect(ConditioningZoneStatus(heartRate: 120, zone: zone) == .inZone)
        #expect(ConditioningZoneStatus(heartRate: 146, zone: zone) == .above)
    }

    @Test("Nudge only after 30 s out of zone, then at most once a minute")
    func sustainedDrift() {
        var monitor = ConditioningZoneMonitor()
        #expect(monitor.update(.above, at: 0) == nil)
        #expect(monitor.update(.above, at: 29) == nil)
        #expect(monitor.update(.above, at: 30) == .above)
        #expect(monitor.update(.above, at: 60) == nil)
        #expect(monitor.update(.above, at: 90) == .above)
    }

    @Test("Back in zone, a different drift or no zone restarts the 30 s")
    func driftResets() {
        var monitor = ConditioningZoneMonitor()
        _ = monitor.update(.below, at: 0)
        #expect(monitor.update(.inZone, at: 20) == nil)
        #expect(monitor.update(.below, at: 25) == nil)
        #expect(monitor.update(.below, at: 50) == nil)
        #expect(monitor.update(.above, at: 55) == nil)
        #expect(monitor.update(nil, at: 70) == nil)
        #expect(monitor.update(.above, at: 71) == nil)
        #expect(monitor.update(.above, at: 101) == .above)
    }

    @Test("The gauge keeps the band in the middle and pins extreme readings to its ends")
    func gaugePlacement() {
        let zone = WatchHeartRateZone(lowerBPM: 120, upperBPM: 140)
        #expect(ConditioningZoneGauge.band(of: zone) == (0.4...0.6))
        #expect(ConditioningZoneGauge.fraction(of: 60, in: zone) == 0)
        #expect(ConditioningZoneGauge.fraction(of: 220, in: zone) == 1)
        #expect(ConditioningZoneGauge.distance(of: 106, from: zone) == 14)
        #expect(ConditioningZoneGauge.distance(of: 130, from: zone) == 0)
        #expect(ConditioningZoneGauge.distance(of: 152, from: zone) == 12)
    }
}
