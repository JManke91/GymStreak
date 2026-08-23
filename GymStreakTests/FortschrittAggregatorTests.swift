//
//  FortschrittAggregatorTests.swift
//  GymStreakTests
//
//  Pins the Fortschritt row aggregation to *sessions* rather than exercise
//  instances. The shipped bug: a routine training one exercise twice in a
//  workout appended two same-dated entries, so the row reported 21 workouts for
//  14 sessions, drew a zero-width sawtooth and computed a 0.0% trend.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct FortschrittAggregatorTests {

    /// Two usages of the same exercise in one workout are one workout, valued by
    /// the better usage — the same reduction the detail chart's session point uses.
    @Test
    func sessionTrainingAnExerciseTwiceCountsOnceAndKeepsTheBetterUsage() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context)
        addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 1)
        #expect(row.sparkline.count == 1)
        // max(1RM(20 kg × 5), 1RM(14 kg × 12)) = max(23.33, 19.6)
        #expect(abs(row.sparkline[0] - 20 * (1 + 5.0 / 30)) < 0.001)
    }

    /// The reporter's shape: every workout trains the exercise heavy *and* light,
    /// with one single-usage workout mixed in. One point per workout, and the
    /// trend must compare comparable ends instead of cancelling to zero.
    @Test
    func mixedSingleAndDoubleUsageSessionsYieldOnePointPerWorkoutWithARealTrend() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        for (index, heavy) in [20.0, 22.0, 24.0].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(heavy, 5, true)], to: session, context: context)
            addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context)
        }
        // A fourth workout that only trains it once — the mix must not change the rule.
        let single = makeSession(startTime: Date(timeIntervalSince1970: 4_000), context: context)
        addExercise(curls, order: 0, sets: [(26, 5, true)], to: single, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 4)
        #expect(row.sparkline.count == 4)
        // Previously the sawtooth: heavy, light, heavy, light … at zero horizontal distance.
        #expect(row.sparkline == row.sparkline.sorted())
        let trend = try #require(row.trendPct)
        // 1RM 20 kg × 5 → 26 kg × 5 is a +30% gain, not the +0.0% the bug reported.
        #expect(abs(trend - 30) < 0.001)
    }

    /// The row's workout count is the same number the exercise detail screen
    /// shows for the all-time window — the two surfaces read one rule.
    @Test
    func workoutCountMatchesTheDetailScreensSessionCount() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        for index in 0..<3 {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context)
            addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context)
        }
        try context.save()

        let sessions = try fetchSessions(context)
        let row = try #require(
            FortschrittAggregator.build(
                sessions: sessions,
                liveExercises: try context.fetch(FetchDescriptor<Exercise>())
            ).first
        )
        let detail = ExerciseProgressAggregator.buildProgress(
            sessions: sessions,
            exerciseName: curls.name,
            exerciseId: curls.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            startDate: .distantPast
        )

        #expect(row.workoutCount == detail.dataPoints.count)
        #expect(row.workoutCount == 3)
    }

    /// Counterweight assistance without a body-mass snapshot compares raw entered
    /// numbers, where *less* is better. Folding two usages of one workout must take
    /// the least assistance, and the sparkline/trend inversion must survive it.
    @Test
    func assistedSessionsFoldToTheLeastAssistanceAndKeepInvertedSemantics() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let first = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(pullUp, order: 0, sets: [(20, 8, true)], to: first, context: context)
        addExercise(pullUp, order: 1, sets: [(15, 5, true)], to: first, context: context)
        let second = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(pullUp, order: 0, sets: [(12, 8, true)], to: second, context: context)
        addExercise(pullUp, order: 1, sets: [(10, 5, true)], to: second, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 2)
        // baseline (15) − folded value, so a rising line still means progress.
        #expect(row.sparkline == [0, 5])
        // 15 kg → 10 kg of assistance is a 33.3% improvement, not a regression.
        let trend = try #require(row.trendPct)
        #expect(abs(trend - 100.0 / 3) < 0.001)
    }

    /// With a body-mass snapshot the assisted series becomes real effective load,
    /// so the fold flips to "highest estimated 1RM" like any resistance exercise.
    @Test
    func assistedSessionWithBodyWeightFoldsToTheHighestEffectiveOneRepMax() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        session.bodyWeightKg = 80
        addExercise(pullUp, order: 0, sets: [(30, 5, true)], to: session, context: context)
        addExercise(pullUp, order: 1, sets: [(20, 5, true)], to: session, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 1)
        // Least assistance (20 kg) is the most effective load: (80 − 20) × (1 + 5/30).
        #expect(abs(row.sparkline[0] - 60 * (1 + 5.0 / 30)) < 0.001)
    }

    // MARK: - Fixtures

    private func build(_ context: ModelContext) throws -> [FortschrittExerciseModel] {
        FortschrittAggregator.build(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>())
        )
    }

    private func fetchSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endTime != nil })
        )
    }

    private func makeSession(startTime: Date, context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        context.insert(session)
        return session
    }

    private func addExercise(
        _ exercise: Exercise,
        order: Int,
        sets: [(Double, Int, Bool)],
        to session: WorkoutSession,
        context: ModelContext
    ) {
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: order,
            exerciseId: exercise.id,
            loadBehavior: exercise.loadBehavior
        )
        workoutExercise.workoutSession = session
        context.insert(workoutExercise)

        for (index, entry) in sets.enumerated() {
            let set = WorkoutSet(
                plannedReps: entry.1,
                actualReps: entry.1,
                plannedWeight: entry.0,
                actualWeight: entry.0,
                restTime: 60,
                order: index
            )
            set.isCompleted = entry.2
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
    }
}
