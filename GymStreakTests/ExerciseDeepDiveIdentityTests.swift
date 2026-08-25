//
//  ExerciseDeepDiveIdentityTests.swift
//  GymStreakTests
//
//  The AI Coach's exercise deep-dive resolves workout rows to a library exercise with the
//  same rule as the chart it sits under — id first, legacy name fallback only where the
//  name is unique.
//
//  It used to carry its own copy of that rule *without* the uniqueness gate, so ambiguous
//  pre-`exerciseId` rows were claimed by every same-named exercise. Found on a device
//  check: the coach read "in den letzten 19 Sitzungen … -43%" beside a chart and a
//  Fortschritt row that both said 15 workouts, on a library holding two "Biceps Curls".
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseDeepDiveIdentityTests {

    /// Two live exercises share a name, so a legacy row naming it belongs to neither and
    /// must be counted for neither. Counting it for **both** is worse than dropping it:
    /// the trend is then computed across two different exercises' loads.
    @Test("Ambiguous legacy rows are counted for neither same-named exercise")
    func ambiguousLegacyRowsAreNotClaimedByEitherVariant() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        // Four attributed dumbbell sessions, climbing.
        for (index, weight) in [14.0, 15.0, 16.0, 17.0].enumerated() {
            let session = makeSession(at: Double(10_000 * (index + 1)), in: context)
            addRow(named: "Biceps Curls", exerciseId: dumbbell.id, weight: weight, to: session, context: context)
        }
        // Four legacy sessions at a barbell load, naming the same exercise. Nothing in the
        // data says which variant these were.
        for (index, weight) in [37.0, 38.0, 39.0, 40.0].enumerated() {
            let session = makeSession(at: Double(1_000 * (index + 1)), in: context)
            addRow(named: "Biceps Curls", exerciseId: nil, weight: weight, to: session, context: context)
        }
        try context.save()

        let aggregator = ExerciseDeepDiveAggregator()
        let input = try #require(
            aggregator.buildInput(exercise: dumbbell, locale: .init(identifier: "en_US"), modelContext: context)
        )

        // Four, not eight: the legacy rows are dropped, exactly as the chart drops them.
        #expect(input.totalSessions == 4)
        // And the peak is a dumbbell load, not a barbell one blended in from nowhere.
        #expect(input.peak.weightKg == 17)

        // "Neither", not "the other one": the barbell variant has no attributed sessions,
        // so it falls under the insufficient-data guard rather than inheriting the legacy
        // rows the dumbbell just refused.
        #expect(
            aggregator.buildInput(
                exercise: barbell,
                locale: .init(identifier: "en_US"),
                modelContext: context
            ) == nil
        )
    }

    /// The cache key decides whether a *new* narrative is generated, and for a free user
    /// that costs a monthly allowance unit. It used to match `exerciseId == nil` with no
    /// name check at all, so any unrelated legacy row in the newest session moved this
    /// exercise's key and spent a unit regenerating an unchanged narrative.
    @Test("An unrelated legacy row does not move the cache key")
    func cacheKeyIgnoresRowsOfOtherExercises() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell)
        context.insert(bench)

        let benchDay = makeSession(at: 1_000, in: context)
        addRow(named: "Bench Press", exerciseId: bench.id, weight: 80, to: benchDay, context: context)
        // Later, and legacy, but a different exercise entirely.
        let squatDay = makeSession(at: 90_000, in: context)
        addRow(named: "Back Squat", exerciseId: nil, weight: 100, to: squatDay, context: context)
        try context.save()

        let stamp = ExerciseDeepDiveAggregator()
            .lastCompletedSetTimestamp(exerciseId: bench.id, modelContext: context)

        #expect(stamp == Date(timeIntervalSince1970: 1_000))
    }

    /// The fallback still has to work — without it, everything logged before
    /// `WorkoutExercise.exerciseId` existed would vanish from the coach's view and every
    /// long-time user's progression would look like it started this year.
    @Test("A uniquely named exercise still picks up its legacy rows")
    func uniqueNameKeepsTheLegacyFallback() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        context.insert(curls)

        for (index, weight) in [37.0, 38.0, 39.0, 40.0].enumerated() {
            let session = makeSession(at: Double(1_000 * (index + 1)), in: context)
            addRow(named: "biceps curls", exerciseId: nil, weight: weight, to: session, context: context)
        }
        try context.save()

        let aggregator = ExerciseDeepDiveAggregator()
        let input = try #require(
            aggregator.buildInput(exercise: curls, locale: .init(identifier: "en_US"), modelContext: context)
        )

        #expect(input.totalSessions == 4)
        #expect(input.peak.weightKg == 40)
    }

    // MARK: - Fixtures

    private func makeSession(at timestamp: TimeInterval, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = Date(timeIntervalSince1970: timestamp)
        session.endTime = Date(timeIntervalSince1970: timestamp + 600)
        context.insert(session)
        return session
    }

    private func addRow(
        named name: String,
        exerciseId: UUID?,
        weight: Double,
        to session: WorkoutSession,
        context: ModelContext
    ) {
        let row = WorkoutExercise(
            exerciseName: name,
            muscleGroups: ["Arms"],
            order: 0,
            exerciseId: exerciseId,
            routineExerciseId: nil,
            loadBehavior: .resistance
        )
        row.workoutSession = session
        context.insert(row)
        // Two completed sets per session, so four sessions clear the aggregator's
        // "at least 4 completed sets" guard.
        for index in 0..<2 {
            let set = WorkoutSet(
                plannedReps: 8,
                actualReps: 8,
                plannedWeight: weight,
                actualWeight: weight,
                restTime: 60,
                order: index
            )
            set.isCompleted = true
            set.workoutExercise = row
            context.insert(set)
        }
    }
}
