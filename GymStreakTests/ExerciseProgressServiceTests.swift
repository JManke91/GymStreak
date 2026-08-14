//
//  ExerciseProgressServiceTests.swift
//  GymStreakTests
import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseProgressServiceTests {

    @Test
    func repeatedExerciseComparesEachRoutineOccurrenceWithItsPreviousCounterpart() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        context.insert(exercise)
        context.insert(routine)

        let previous = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 1_000),
            performances: [
                (order: 1, weight: 13, reps: 12, routineExerciseId: nil),
                (order: 0, weight: 20, reps: 5, routineExerciseId: nil)
            ],
            exercise: exercise,
            context: context
        )
        let current = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 2_000),
            performances: [
                (order: 0, weight: 20, reps: 5, routineExerciseId: nil),
                (order: 1, weight: 13, reps: 12, routineExerciseId: nil)
            ],
            exercise: exercise,
            context: context
        )
        try context.save()

        let results = await makeService(context: context)
            .compareWithPrevious(workout: current)

        #expect(previous.workoutExercisesList.count == 2)
        #expect(results.count == 2)
        #expect(results[0].previousPerformance?.sets.first?.weight == 20)
        #expect(results[1].previousPerformance?.sets.first?.weight == 13)

        // Each row names the exercise it describes, in `order`. Callers key on this
        // instead of pairing arrays positionally, and a workout that repeats an exercise
        // is exactly the case where the same-name key they used before collided.
        let currentExercises = current.workoutExercisesList.sorted { $0.order < $1.order }
        #expect(results.map(\.workoutExerciseId) == currentExercises.map(\.id))
        #expect(results[0].exerciseName == results[1].exerciseName)
    }

    /// A failed history lookup must produce **no** rows, not rows without a predecessor.
    ///
    /// The two are rendered very differently: a row with `previousPerformance == nil` is
    /// `isFirstTime`, which the save sheet badges "New exercise" and the AI analysis
    /// treats as having nothing to compare. Degrading into that would assert something
    /// false about the user's history instead of showing nothing (audit P1.6).
    @Test
    func failedHistoryLookupYieldsNoRowsRatherThanFalseFirstTimeRows() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        context.insert(exercise)
        context.insert(routine)

        let current = WorkoutSession(routine: routine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_100)
        context.insert(current)
        addPerformance(exercise, weight: 21, reps: 5, order: 0, to: current, context: context)
        try context.save()

        let results = await ExerciseProgressService(historyProvider: FailingHistorySnapshotProvider())
            .compareWithPrevious(workout: current)

        #expect(results.isEmpty)
    }

    @Test
    func routineSlotIdentitySurvivesExerciseReordering() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        let routine = Routine(name: "Pull")
        let heavySlotId = UUID()
        let highRepSlotId = UUID()
        context.insert(exercise)
        context.insert(routine)

        _ = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 1_000),
            performances: [
                (order: 0, weight: 20, reps: 5, routineExerciseId: heavySlotId),
                (order: 1, weight: 13, reps: 12, routineExerciseId: highRepSlotId)
            ],
            exercise: exercise,
            context: context
        )
        let current = makeCompletedSession(
            routine: routine,
            startTime: Date(timeIntervalSince1970: 2_000),
            performances: [
                (order: 0, weight: 13, reps: 12, routineExerciseId: highRepSlotId),
                (order: 1, weight: 20, reps: 5, routineExerciseId: heavySlotId)
            ],
            exercise: exercise,
            context: context
        )
        try context.save()

        let results = await makeService(context: context)
            .compareWithPrevious(workout: current)

        #expect(results[0].previousPerformance?.sets.first?.weight == 13)
        #expect(results[1].previousPerformance?.sets.first?.weight == 20)
    }

    @Test
    func sameNameEquipmentVariantsRemainSeparate() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        let routine = Routine(name: "Pull")
        context.insert(barbell)
        context.insert(dumbbell)
        context.insert(routine)

        let previous = WorkoutSession(routine: routine)
        previous.startTime = Date(timeIntervalSince1970: 1_000)
        previous.endTime = Date(timeIntervalSince1970: 1_600)
        context.insert(previous)
        addPerformance(barbell, weight: 30, reps: 6, order: 0, to: previous, context: context)
        addPerformance(dumbbell, weight: 13, reps: 12, order: 1, to: previous, context: context)

        let current = WorkoutSession(routine: routine)
        current.startTime = Date(timeIntervalSince1970: 2_000)
        current.endTime = Date(timeIntervalSince1970: 2_600)
        context.insert(current)
        addPerformance(barbell, weight: 32, reps: 6, order: 0, to: current, context: context)
        addPerformance(dumbbell, weight: 14, reps: 12, order: 1, to: current, context: context)
        try context.save()

        let results = await makeService(context: context)
            .compareWithPrevious(workout: current)

        #expect(results[0].previousPerformance?.sets.first?.weight == 30)
        #expect(results[1].previousPerformance?.sets.first?.weight == 13)
    }

    /// The service over the real off-main boundary (audit P1.6).
    ///
    /// Not a double: the previous-performance half runs in `SwiftDataHistorySnapshotStore`
    /// against `context.container`, so these cases still exercise the fetch, the identity
    /// matching and the actor hop end to end. They rely on the caller having saved
    /// `context` first — the model actor's own context cannot see unsaved changes.
    /// Deliberately not `private`: `ExerciseProgressLegacyIdentityTests` extends this
    /// suite from another file.
    func makeService(context: ModelContext) -> ExerciseProgressService {
        ExerciseProgressService(
            historyProvider: SwiftDataHistorySnapshotProvider(modelContainer: context.container)
        )
    }

    private func makeCompletedSession(
        routine: Routine,
        startTime: Date,
        performances: [(order: Int, weight: Double, reps: Int, routineExerciseId: UUID?)],
        exercise: Exercise,
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(routine: routine)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        context.insert(session)

        for performance in performances {
            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                muscleGroups: exercise.muscleGroups,
                order: performance.order,
                exerciseId: exercise.id
            )
            workoutExercise.routineExerciseId = performance.routineExerciseId
            workoutExercise.workoutSession = session
            context.insert(workoutExercise)

            let set = WorkoutSet(
                plannedReps: performance.reps,
                actualReps: performance.reps,
                plannedWeight: performance.weight,
                actualWeight: performance.weight,
                restTime: 60,
                order: 0
            )
            set.isCompleted = true
            set.workoutExercise = workoutExercise
            context.insert(set)
        }

        return session
    }

    func addPerformance(
        _ exercise: Exercise,
        weight: Double,
        reps: Int,
        order: Int,
        to session: WorkoutSession,
        context: ModelContext
    ) {
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: order,
            exerciseId: exercise.id
        )
        workoutExercise.workoutSession = session
        context.insert(workoutExercise)

        let set = WorkoutSet(
            plannedReps: reps,
            actualReps: reps,
            plannedWeight: weight,
            actualWeight: weight,
            restTime: 60,
            order: 0
        )
        set.isCompleted = true
        set.workoutExercise = workoutExercise
        context.insert(set)
    }
}

/// A history boundary that always fails, for the "no rows, not false first-time rows"
/// contract. Only `fetchPreviousPerformances` is reachable from `ExerciseProgressService`;
/// the rest are unreachable requirements of the same protocol.
private struct FailingHistorySnapshotProvider: HistorySnapshotProviding {
    struct Failure: Error {}

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        throw Failure()
    }

    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] {
        throw Failure()
    }

    func fetchPRDetails(sessionID: UUID) async throws -> [UUID: PersonalRecordService.PRDetail] {
        throw Failure()
    }

    func fetchExerciseProgress(
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int
    ) async throws -> ExerciseProgressSnapshot {
        throw Failure()
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] {
        throw Failure()
    }
}
