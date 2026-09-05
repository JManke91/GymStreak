//
//  WorkoutAnalysisAggregatorTests.swift
//  GymStreakTests
//
//  The workout analysis compares a session against the previous session **of the same
//  routine**, and "same routine" used to mean "same denormalized `routineName`". Renaming
//  a routine therefore orphaned it from its own history: the next workout found no
//  predecessor and the surface reported nothing to compare, which also made a report of
//  "no Coach analysis on a workout that clearly has one" ambiguous.
//
//  Matching is on the routine's id now, with the name kept as the fallback for a session
//  whose template is gone — a deleted routine, a watch workout, a HealthKit recovery.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutAnalysisAggregatorTests {

    private let aggregator = WorkoutAnalysisAggregator()

    @Test("A renamed routine still finds its own history")
    func previousSessionSurvivesARoutineRename() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = makeRoutine(name: "Push", context: context)

        let old = makeSession(routine: routine, daysAgo: 7, context: context)
        #expect(old.routineName == "Push", "fixture sanity: the name is denormalized at creation")

        // The user renames the routine, then trains it again.
        routine.name = "Push A"
        let current = makeSession(routine: routine, daysAgo: 0, context: context)
        try context.save()

        #expect(current.routineName != old.routineName, "fixture sanity: the two names differ")
        #expect(aggregator.hasPreviousSession(session: current, modelContext: context))
    }

    /// The id match must win over the name match, not merely exist beside it: a second
    /// routine sharing the name has the *more recent* session, so name matching would
    /// return the wrong one.
    @Test("A different routine with the same name is not mistaken for the same routine")
    func routineIdentityBeatsASharedName() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let mine = makeRoutine(name: "Push", context: context)
        let namesake = makeRoutine(name: "Push", context: context)

        let minePrevious = makeSession(routine: mine, daysAgo: 14, context: context)
        makeSession(routine: namesake, daysAgo: 2, context: context)
        let current = makeSession(routine: mine, daysAgo: 0, context: context)
        try context.save()

        let input = aggregator.buildInput(
            session: current,
            locale: Locale(identifier: "en_US"),
            modelContext: context,
            comparisons: comparisons(for: current)
        )

        // 14 days back is this routine's own previous session; the namesake's is 2 days back.
        #expect(input?.daysSincePrevious == 14)
        #expect(minePrevious.routine?.id == mine.id)
    }

    /// The id match is a `fetchLimit = 1` fetch, so it depends on the store applying the
    /// sort before the limit: with two own-routine predecessors the newest has to win, or
    /// `daysSincePrevious` and every figure derived from the comparison describe the wrong
    /// session.
    @Test("The newest session of the same routine wins, not just any of them")
    func newestOwnRoutineSessionWins() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = makeRoutine(name: "Push", context: context)
        makeSession(routine: routine, daysAgo: 21, context: context)
        makeSession(routine: routine, daysAgo: 3, context: context)
        let current = makeSession(routine: routine, daysAgo: 0, context: context)
        try context.save()

        let input = aggregator.buildInput(
            session: current,
            locale: Locale(identifier: "en_US"),
            modelContext: context,
            comparisons: comparisons(for: current)
        )

        #expect(input?.daysSincePrevious == 3)
    }

    /// Sharing a name does not make another routine's session ours. Before the id match
    /// this was the only rule; now that a routine without history falls back to the name,
    /// the fallback has to exclude candidates that carry a *different* template.
    @Test("A routine with no history of its own does not borrow a namesake's session")
    func aRoutineWithoutHistoryDoesNotBorrowANamesakeSession() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let mine = makeRoutine(name: "Push", context: context)
        let namesake = makeRoutine(name: "Push", context: context)

        makeSession(routine: namesake, daysAgo: 4, context: context)
        let current = makeSession(routine: mine, daysAgo: 0, context: context)
        try context.save()

        #expect(!aggregator.hasPreviousSession(session: current, modelContext: context))
    }

    /// …but a predecessor with no template at all still qualifies: a watch-recorded or
    /// HealthKit-recovered session carries only the name.
    @Test("A templateless predecessor still matches a session that has a routine")
    func templatelessPredecessorMatchesATemplatedSession() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = makeRoutine(name: "Push", context: context)
        makeSession(routine: nil, name: "Push", daysAgo: 4, context: context)
        let current = makeSession(routine: routine, daysAgo: 0, context: context)
        try context.save()

        #expect(aggregator.hasPreviousSession(session: current, modelContext: context))
    }

    @Test("A session whose template is gone still matches on its stored name")
    func templatelessSessionsMatchOnTheName() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        makeSession(routine: nil, name: "Push", daysAgo: 3, context: context)
        let current = makeSession(routine: nil, name: "Push", daysAgo: 0, context: context)
        try context.save()

        #expect(aggregator.hasPreviousSession(session: current, modelContext: context))
    }

    @Test("Two sessions with neither a template nor a name are not the same routine")
    func unnamedTemplatelessSessionsDoNotMatch() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        makeSession(routine: nil, name: "", daysAgo: 3, context: context)
        let current = makeSession(routine: nil, name: "", daysAgo: 0, context: context)
        try context.save()

        #expect(!aggregator.hasPreviousSession(session: current, modelContext: context))
    }

    @Test("An unfinished session is not a predecessor")
    func unfinishedSessionsAreIgnored() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routine = makeRoutine(name: "Push", context: context)
        let abandoned = makeSession(routine: routine, daysAgo: 3, context: context)
        abandoned.endTime = nil
        let current = makeSession(routine: routine, daysAgo: 0, context: context)
        try context.save()

        #expect(!aggregator.hasPreviousSession(session: current, modelContext: context))
    }

    // MARK: - Fixtures

    /// One comparison per exercise, each carrying a previous performance — without one
    /// every exercise reads as first-time and `buildInput` gates the session out before
    /// the comparison it resolved can be inspected.
    private func comparisons(for session: WorkoutSession) -> [ExerciseComparisonResult] {
        session.workoutExercisesList.map { exercise in
            ExerciseComparisonResult(
                workoutExerciseId: exercise.id,
                exerciseName: exercise.exerciseName,
                loadBehavior: .resistance,
                currentPerformance: .init(
                    sets: exercise.setsList.enumerated().map { index, set in
                        .init(
                            setNumber: index + 1,
                            currentReps: set.actualReps,
                            currentWeight: set.actualWeight,
                            previousReps: set.actualReps,
                            previousWeight: set.actualWeight - 2.5,
                            isCompleted: set.isCompleted
                        )
                    },
                    totalVolume: 1_000,
                    effectiveTotalVolume: 1_000,
                    completedSetsCount: exercise.setsList.count,
                    totalReps: 10
                ),
                previousPerformance: .init(
                    date: session.startTime.addingTimeInterval(-14 * 86_400),
                    routineName: session.routineName,
                    sets: [.init(reps: 5, weight: 97.5, isCompleted: true)],
                    effectiveTotalVolume: 975
                )
            )
        }
    }

    private func makeRoutine(name: String, context: ModelContext) -> Routine {
        let routine = Routine(name: name)
        context.insert(routine)
        return routine
    }

    @discardableResult
    private func makeSession(
        routine: Routine?,
        name: String? = nil,
        daysAgo: Int,
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(routine: routine)
        if let name { session.routineName = name }
        session.startTime = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        session.endTime = session.startTime.addingTimeInterval(3_600)
        context.insert(session)

        let exercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["chest"],
            order: 0,
            exerciseId: UUID()
        )
        exercise.workoutSession = session
        context.insert(exercise)
        for index in 0..<2 {
            let set = WorkoutSet(
                plannedReps: 5,
                actualReps: 5,
                plannedWeight: 100,
                actualWeight: 100,
                restTime: 60,
                order: index
            )
            set.isCompleted = true
            set.workoutExercise = exercise
            context.insert(set)
        }
        return session
    }
}
