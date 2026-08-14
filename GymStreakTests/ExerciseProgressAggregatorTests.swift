//
//  ExerciseProgressAggregatorTests.swift
//  GymStreakTests
//
//  Coverage for the pure chart aggregation extracted from `ExerciseProgressService`
//  (audit P1.2). The logic shipped with none: `fetchProgressData` had zero tests, so
//  the extraction is pinned here rather than trusted.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseProgressAggregatorTests {

    @Test
    func buildsOneDataPointPerSessionAggregatingItsCompletedSets() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        makeSession(
            startTime: Date(timeIntervalSince1970: 1_000),
            sets: [(weight: 100, reps: 5, completed: true), (weight: 90, reps: 8, completed: true)],
            exercise: exercise,
            context: context
        )
        makeSession(
            startTime: Date(timeIntervalSince1970: 2_000),
            sets: [(weight: 110, reps: 5, completed: true)],
            exercise: exercise,
            context: context
        )
        try context.save()

        let result = ExerciseProgressAggregator.buildProgress(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            startDate: .distantPast
        )

        #expect(result.dataPoints.count == 2)
        // Ascending by date regardless of the fetch order the store hands over —
        // the chart's trend reads first vs. last.
        #expect(result.dataPoints[0].date < result.dataPoints[1].date)
        #expect(result.dataPoints[0].maxWeight == 100)
        #expect(result.dataPoints[0].totalVolume == 100 * 5 + 90 * 8)
        #expect(result.dataPoints[0].totalSets == 2)
        #expect(result.dataPoints[0].totalReps == 13)
        #expect(result.dataPoints[1].maxWeight == 110)
    }

    @Test
    func incompleteSetsAndSessionsOutsideTheWindowAreExcluded() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        makeSession(
            startTime: Date(timeIntervalSince1970: 1_000),
            sets: [(weight: 200, reps: 5, completed: true)],
            exercise: exercise,
            context: context
        )
        makeSession(
            startTime: Date(timeIntervalSince1970: 5_000),
            sets: [(weight: 100, reps: 5, completed: true), (weight: 999, reps: 1, completed: false)],
            exercise: exercise,
            context: context
        )
        try context.save()

        let result = ExerciseProgressAggregator.buildProgress(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            startDate: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].maxWeight == 100)
        #expect(result.dataPoints[0].totalSets == 1)
    }

    /// The legacy name fallback must stay gated on library uniqueness — an untagged
    /// row is ambiguous when two live exercises share a name, so it belongs to neither.
    @Test
    func ambiguousLegacyRowsAreDroppedWhenTheNameIsNotUnique() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let session = WorkoutSession(routine: nil)
        session.startTime = Date(timeIntervalSince1970: 1_000)
        session.endTime = Date(timeIntervalSince1970: 1_600)
        context.insert(session)
        // No `exerciseId` — a pre-tagging history row.
        addExercise(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: session, context: context)
        try context.save()

        let liveExercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(ExerciseProgressAggregator.isNameUnique("Biceps Curls", in: liveExercises) == false)

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: liveExercises,
            exerciseName: "Biceps Curls",
            exerciseId: barbell.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        #expect(snapshot.data.dataPoints.isEmpty)
        #expect(snapshot.recentSessions.isEmpty)
    }

    @Test
    func recentSessionsAreNewestFirstAndCappedByTheLimit() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        for index in 0..<5 {
            makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                sets: [(weight: Double(100 + index), reps: 5, completed: true)],
                exercise: exercise,
                context: context
            )
        }
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentSessions(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            limit: 3
        )

        #expect(result.count == 3)
        #expect(result[0].date > result[1].date)
        #expect(result[0].bestSet?.weight == 104)
        // Ignores the chart window on purpose — the list is all-time.
        #expect(result[2].bestSet?.weight == 102)
    }

    /// The recent-session list must never carry an entry with no completed sets:
    /// the screen renders each as a card of set chips.
    @Test
    func recentSessionsSkipSessionsWithoutCompletedSets() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        makeSession(
            startTime: Date(timeIntervalSince1970: 2_000),
            sets: [(weight: 100, reps: 5, completed: false)],
            exercise: exercise,
            context: context
        )
        makeSession(
            startTime: Date(timeIntervalSince1970: 1_000),
            sets: [(weight: 80, reps: 5, completed: true)],
            exercise: exercise,
            context: context
        )
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentSessions(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            limit: 8
        )

        #expect(result.count == 1)
        #expect(result[0].sets.count == 1)
        #expect(result[0].sets[0].weight == 80)
    }

    @Test
    func loadBehaviorResolvesByIdThenNameAndFallsBackToResistance() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let assisted = Exercise(name: "Assisted Pull-Up")
        assisted.loadBehavior = .counterweightAssistance
        context.insert(assisted)
        try context.save()

        let live = try context.fetch(FetchDescriptor<Exercise>())

        #expect(
            ExerciseProgressAggregator.loadBehavior(
                exerciseId: assisted.id, exerciseName: "irrelevant", in: live
            ) == .counterweightAssistance
        )
        #expect(
            ExerciseProgressAggregator.loadBehavior(
                exerciseId: nil, exerciseName: "assisted pull-up", in: live
            ) == .counterweightAssistance
        )
        // Deleted from the library — the chart still renders, as plain resistance.
        #expect(
            ExerciseProgressAggregator.loadBehavior(
                exerciseId: UUID(), exerciseName: "Gone", in: live
            ) == .resistance
        )
    }

    // MARK: - Fixtures

    private func fetchSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endTime != nil })
        )
    }

    @discardableResult
    private func makeSession(
        startTime: Date,
        sets: [(weight: Double, reps: Int, completed: Bool)],
        exercise: Exercise,
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        context.insert(session)
        addExercise(
            named: exercise.name,
            exerciseId: exercise.id,
            sets: sets.map { ($0.weight, $0.reps, $0.completed) },
            to: session,
            context: context
        )
        return session
    }

    private func addExercise(
        named name: String,
        exerciseId: UUID?,
        sets: [(Double, Int, Bool)],
        to session: WorkoutSession,
        context: ModelContext
    ) {
        let workoutExercise = WorkoutExercise(
            exerciseName: name,
            muscleGroups: ["Chest"],
            order: 0,
            exerciseId: exerciseId
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
