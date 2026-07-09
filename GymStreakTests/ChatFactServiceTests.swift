//
//  ChatFactServiceTests.swift
//  GymStreakTests
//
//  Validates the fact lines the chat tools feed the model — the grounding
//  source of truth. If these numbers are right and the model must quote them
//  verbatim, answers stay grounded. Uses a real in-memory SwiftData store.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ChatFactServiceTests {

    private func makeContext() -> ModelContext {
        ModelContext(InMemoryModelContainer.make())
    }

    @discardableResult
    private func seedCompletedSession(
        context: ModelContext,
        routineName: String,
        exercise: Exercise,
        sets: [(weight: Double, reps: Int)],
        start: Date
    ) -> WorkoutSession {
        let routine = Routine(name: routineName)
        context.insert(routine)
        let session = WorkoutSession(routine: routine)
        session.routineName = routineName
        session.startTime = start
        session.endTime = start.addingTimeInterval(3600)
        context.insert(session)

        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: ["Chest"],
            order: 0,
            exerciseId: exercise.id
        )
        context.insert(workoutExercise)
        workoutExercise.workoutSession = session

        for (index, entry) in sets.enumerated() {
            let set = WorkoutSet(
                plannedReps: entry.reps,
                actualReps: entry.reps,
                plannedWeight: entry.weight,
                actualWeight: entry.weight,
                restTime: 60,
                order: index
            )
            set.isCompleted = true
            context.insert(set)
            set.workoutExercise = workoutExercise
        }

        try? context.save()
        return session
    }

    // MARK: - PR

    @Test func exercisePRReportsBestSetAndEstimated1RM() {
        let context = makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        // Best est-1RM: 100×5 → 116.7 (beats 90×8 → 114 and 80×5 → 93.3).
        seedCompletedSession(context: context, routineName: "Push", exercise: exercise,
                             sets: [(80, 5), (100, 5), (90, 8)], start: Date().addingTimeInterval(-86_400))

        let line = ChatFactService(modelContext: context).exercisePRFacts(exerciseName: "Bench Press")
        #expect(line.contains("100 kg x 5 reps"))
        #expect(line.contains("116.7 kg"))
        #expect(!line.contains("__NO_MATCH__"))
    }

    @Test func exercisePRAggregatesSameNameVariants() {
        let context = makeContext()
        let barbell = Exercise(name: "Biceps Curls")
        let dumbbell = Exercise(name: "Biceps Curls")
        context.insert(barbell)
        context.insert(dumbbell)
        // barbell 30×10 → est 40; dumbbell 20×12 → est 28. Best across both = 30×10.
        seedCompletedSession(context: context, routineName: "Arms", exercise: barbell,
                             sets: [(30, 10)], start: Date().addingTimeInterval(-172_800))
        seedCompletedSession(context: context, routineName: "Arms", exercise: dumbbell,
                             sets: [(20, 12)], start: Date().addingTimeInterval(-86_400))

        let line = ChatFactService(modelContext: context).exercisePRFacts(exerciseName: "Biceps Curls")
        #expect(line.contains("30 kg x 10 reps"))
        #expect(!line.contains("__NO_MATCH__"))
    }

    @Test func exercisePRUnknownReturnsMarkerWithLibrary() {
        let context = makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        try? context.save()

        let line = ChatFactService(modelContext: context).exercisePRFacts(exerciseName: "Kreuzheben")
        #expect(line.contains("__NO_MATCH__"))
        #expect(line.contains("Squat")) // real library handed to the model
    }

    // MARK: - History

    @Test func historyCountsThisWeek() {
        let context = makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        seedCompletedSession(context: context, routineName: "Push", exercise: exercise,
                             sets: [(100, 5)], start: Date())

        let line = ChatFactService(modelContext: context).workoutHistoryFacts(timeframe: .thisWeek)
        #expect(line.contains("This week"))
        #expect(line.contains("1 workout"))
    }

    @Test func historyAllTimeNamesMostRecentWorkout() {
        let context = makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        seedCompletedSession(context: context, routineName: "LegDay", exercise: exercise,
                             sets: [(100, 5)], start: Date().addingTimeInterval(-86_400 * 40))

        let line = ChatFactService(modelContext: context).workoutHistoryFacts(timeframe: .allTime)
        #expect(line.contains("All time"))
        #expect(line.contains("LegDay")) // resolves "my last workout" beyond week/month windows
    }

    // MARK: - Next workout

    @Test func nextWorkoutWithNoScheduleSaysNonePlanned() {
        let line = ChatFactService(modelContext: makeContext()).nextWorkoutFacts()
        #expect(line.contains("No routines are scheduled"))
    }
}
