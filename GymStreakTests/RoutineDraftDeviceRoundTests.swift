//
//  RoutineDraftDeviceRoundTests.swift
//  GymStreakTests
//
//  Replays of what the iPhone's on-device model actually produced in device rounds of
//  the AI routine draft (docs/ai-coach-routine-drafting.md §4a) — the cases the macOS
//  probe did not reproduce, pinned at the level the person sees them.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftDeviceRoundTests {

    /// Device round 10 (iPhone): "Push-Test: Bankdrücken 3x8-12 mit 60kg, 90 Sekunden
    /// Pause" reviewed as Bankdrücken without its 60 kg, plus an exercise named "Pause"
    /// that asked for its set count.
    @Test("Round 10 replay: the typed load is recovered and 'Pause' is no exercise")
    func roundTenReplay() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bankdrücken"])
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push-Test", [
            routineDraftEntry("Bankdrücken", sets: 3, reps: 8, weight: 0, repRange: (8, 12), rest: (.seconds, 90)),
            routineDraftEntry("Pause", sets: 0, reps: 0, weight: 0),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push-Test: Bankdrücken 3x8-12 mit 60kg, 90 Sekunden Pause"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.rows.map(\.name) == ["Bankdrücken"])
        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first?.first)
        #expect(written.targetRepMin == 8 && written.targetRepMax == 12)
        #expect(written.sets.count == 3)
        #expect(written.sets.allSatisfy { $0.weight == 60 && $0.reps == 8 && $0.restTime == 90 })
    }

    @Test("A refused load and a missed range are read from the exercise's own words, not a neighbour's")
    func figuresComeFromTheExercisesOwnWords() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bankdrücken", "Kniebeugen"])
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push", [
            routineDraftEntry("Bankdrücken", sets: 3, reps: 8, weight: 12),
            routineDraftEntry("Kniebeugen", sets: 5, reps: 5, weight: 0),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push: Bankdrücken 3x8-12 mit 60kg, Kniebeugen 5x5 mit 100kg"
        harness.viewModel.submit()
        await harness.settle()
        harness.viewModel.createRoutine()

        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.count == 2)
        #expect(written[0].sets.allSatisfy { $0.weight == 60 })
        #expect(written[0].targetRepMin == 8 && written[0].targetRepMax == 12)
        #expect(written[1].sets.allSatisfy { $0.weight == 100 })
        #expect(written[1].targetRepMin == nil)
    }

    /// Architecture review, 2026-09-27: the model left out the squat, so the pull-ups'
    /// stretch of words ran over the squat's 100 kg and 8–12.
    @Test("An exercise the model left out lends its figures to no neighbour")
    func omittedExerciseLendsNoFigures() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Klimmzüge", "Dips"])
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Pull", [
            routineDraftEntry("Klimmzüge", sets: 3, reps: 8, weight: 0),
            routineDraftEntry("Dips", sets: 3, reps: 10, weight: 0),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Pull: Klimmzüge 3x8, Kniebeuge 5x5 100kg 8-12, Dips 3x10"
        harness.viewModel.submit()
        await harness.settle()
        harness.viewModel.createRoutine()

        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.allSatisfy { $0.targetRepMin == nil })
        #expect(written.allSatisfy { $0.sets.allSatisfy { $0.weight == 0 } })
    }
}
