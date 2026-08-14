//
//  ChatFactProviderTests.swift
//  GymStreakTests
//
//  Validates the fact lines the chat tools feed the model — the grounding
//  source of truth. If these numbers are right and the model must quote them
//  verbatim, answers stay grounded. Uses a real in-memory SwiftData store.
//
//  Since audit P1.3 these go through the real boundary — `ChatFactProvider`'s
//  `@concurrent` hop into `ChatFactStore`'s model actor — rather than calling a
//  main-actor service directly, so the fetch ordering and the actor hop are covered
//  too. The main-actor responsiveness of that hop is asserted separately, in
//  `SwiftDataHistorySnapshotStoreTests`.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ChatFactProviderTests {

    /// Seeds through one context and reads through the provider's own actor-owned
    /// context, exactly as production does (chat facts are written by the app's main
    /// context and read by the fact actor).
    private func makeContainer() -> ModelContainer {
        InMemoryModelContainer.make()
    }

    /// Typed as the existential on purpose: production dispatches through
    /// `any ChatFactProviding` (the tools hold `let facts: any ChatFactProviding`),
    /// and the `@concurrent` guarantee has to survive the witness.
    private func makeProvider(_ container: ModelContainer) -> any ChatFactProviding {
        ChatFactProvider(modelContainer: container)
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

    @Test func exercisePRReportsBestSetAndEstimated1RM() async {
        let container = makeContainer()
        let context = ModelContext(container)
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        // Best est-1RM: 100×5 → 116.7 (beats 90×8 → 114 and 80×5 → 93.3).
        seedCompletedSession(context: context, routineName: "Push", exercise: exercise,
                             sets: [(80, 5), (100, 5), (90, 8)], start: Date().addingTimeInterval(-86_400))

        let line = await makeProvider(container).exercisePRFacts(exerciseName: "Bench Press")
        #expect(line.contains("100 kg x 5 reps"))
        #expect(line.contains("116.7 kg"))
        #expect(!line.contains("__NO_MATCH__"))
    }

    @Test func exercisePRAggregatesSameNameVariants() async {
        let container = makeContainer()
        let context = ModelContext(container)
        let barbell = Exercise(name: "Biceps Curls")
        let dumbbell = Exercise(name: "Biceps Curls")
        context.insert(barbell)
        context.insert(dumbbell)
        // barbell 30×10 → est 40; dumbbell 20×12 → est 28. Best across both = 30×10.
        seedCompletedSession(context: context, routineName: "Arms", exercise: barbell,
                             sets: [(30, 10)], start: Date().addingTimeInterval(-172_800))
        seedCompletedSession(context: context, routineName: "Arms", exercise: dumbbell,
                             sets: [(20, 12)], start: Date().addingTimeInterval(-86_400))

        let line = await makeProvider(container).exercisePRFacts(exerciseName: "Biceps Curls")
        #expect(line.contains("30 kg x 10 reps"))
        #expect(!line.contains("__NO_MATCH__"))
    }

    @Test func exercisePRUnknownReturnsMarkerWithLibrary() async {
        let container = makeContainer()
        let context = ModelContext(container)
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        try? context.save()

        let line = await makeProvider(container).exercisePRFacts(exerciseName: "Kreuzheben")
        #expect(line.contains("__NO_MATCH__"))
        #expect(line.contains("Squat")) // real library handed to the model
    }

    // MARK: - History

    @Test func historyCountsThisWeek() async {
        let container = makeContainer()
        let context = ModelContext(container)
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        seedCompletedSession(context: context, routineName: "Push", exercise: exercise,
                             sets: [(100, 5)], start: Date())

        let line = await makeProvider(container).workoutHistoryFacts(timeframe: .thisWeek)
        #expect(line.contains("This week"))
        #expect(line.contains("1 workout"))
    }

    @Test func historyAllTimeNamesMostRecentWorkout() async {
        let container = makeContainer()
        let context = ModelContext(container)
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        seedCompletedSession(context: context, routineName: "LegDay", exercise: exercise,
                             sets: [(100, 5)], start: Date().addingTimeInterval(-86_400 * 40))

        let line = await makeProvider(container).workoutHistoryFacts(timeframe: .allTime)
        #expect(line.contains("All time"))
        #expect(line.contains("LegDay")) // resolves "my last workout" beyond week/month windows
    }

    // MARK: - Next workout

    @Test func nextWorkoutWithNoScheduleSaysNonePlanned() async {
        let line = await makeProvider(makeContainer()).nextWorkoutFacts()
        #expect(line.contains("No routines are scheduled"))
    }

    /// `nextWorkoutFacts` dates each routine against its last completion, which means
    /// walking the `WorkoutSession.routine` relationship. Its fetch deliberately
    /// prefetches only `\.routine` (not the exercise/set graph), so this covers that
    /// the narrower fetch still resolves the relationship.
    @Test func nextWorkoutDatesRoutineAgainstItsLastCompletion() async {
        let container = makeContainer()
        let context = ModelContext(container)
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        let routine = Routine(name: "Push")
        context.insert(routine)
        let schedule = RoutineSchedule(type: .weekdays, weekdays: [1, 2, 3, 4, 5, 6, 7])
        context.insert(schedule)
        routine.schedule = schedule

        let session = WorkoutSession(routine: routine)
        session.routineName = "Push"
        session.startTime = Date().addingTimeInterval(-86_400)
        session.endTime = session.startTime.addingTimeInterval(3600)
        context.insert(session)
        try? context.save()

        let line = await makeProvider(container).nextWorkoutFacts()
        #expect(line.contains("Push"))
        #expect(!line.contains("No routines are scheduled"))
    }
}
