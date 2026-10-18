//
//  WorkoutDetailExerciseGroupTests.swift
//  GymStreakTests
//
//  The History detail's exercise rows: a recorded superset becomes one lettered
//  group, standalone exercises stay single rows (docs/superset-feature.md,
//  "History Detail - Superset Display").
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutDetailExerciseGroupTests {

    @Test("A recorded superset becomes one lettered group; standalone exercises stay single")
    func groupsSupersetMembers() throws {
        let (context, session) = makeSession()
        let supersetId = UUID()
        let bench = exercise("Bench Press", order: 0, in: session)
        let fly = exercise("Cable Fly", order: 1, superset: supersetId, position: 0, in: session)
        let pushdown = exercise("Triceps Pushdown", order: 2, superset: supersetId, position: 1, in: session)
        try context.save()

        let groups = WorkoutDetailExerciseGroup.make(from: session)

        #expect(groups.map { $0.exercises.map(\.name) } == [["Bench Press"], ["Cable Fly", "Triceps Pushdown"]])
        #expect(groups.map(\.supersetLetter) == [nil, "A"])
        #expect(groups[0].id == bench.id)
        #expect(groups[1].id == supersetId)
        #expect(groups[1].exercises.map(\.id) == [fly.id, pushdown.id])
        #expect(groups[1].exercises[0].sets.map(\.reps) == [10, 8], "each member keeps its set values")
    }

    @Test("Superset letters follow first appearance in order, like the active workout")
    func lettersFollowOrder() throws {
        let (context, session) = makeSession()
        let first = UUID()
        let second = UUID()
        exercise("Row", order: 0, superset: first, position: 0, in: session)
        exercise("Curl", order: 1, superset: first, position: 1, in: session)
        exercise("Squat", order: 2, in: session)
        exercise("Lunge", order: 3, superset: second, position: 0, in: session)
        exercise("Calf Raise", order: 4, superset: second, position: 1, in: session)
        try context.save()

        let groups = WorkoutDetailExerciseGroup.make(from: session)

        #expect(groups.map(\.supersetLetter) == ["A", nil, "B"])
    }

    @Test("A superset with a single member is drawn as a standalone exercise")
    func singleMemberSupersetIsStandalone() throws {
        let (context, session) = makeSession()
        exercise("Bench Press", order: 0, superset: UUID(), position: 0, in: session)
        exercise("Squat", order: 1, in: session)
        try context.save()

        let groups = WorkoutDetailExerciseGroup.make(from: session)

        #expect(groups.count == 2)
        #expect(groups.map(\.supersetLetter) == [nil, nil])
    }

    @Test("A workout without supersets is one row per exercise, in order")
    func noSupersets() throws {
        let (context, session) = makeSession()
        exercise("Squat", order: 1, in: session)
        exercise("Bench Press", order: 0, in: session)
        try context.save()

        let groups = WorkoutDetailExerciseGroup.make(from: session)

        #expect(groups.map { $0.exercises.map(\.name) } == [["Bench Press"], ["Squat"]])
        #expect(groups.allSatisfy { $0.supersetLetter == nil })
    }

    // MARK: - Fixtures

    private func makeSession() -> (ModelContext, WorkoutSession) {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = WorkoutSession(routine: nil)
        session.routineName = "Push"
        context.insert(session)
        return (context, session)
    }

    @discardableResult
    private func exercise(
        _ name: String,
        order: Int,
        superset: UUID? = nil,
        position: Int = 0,
        in session: WorkoutSession
    ) -> WorkoutExercise {
        let exercise = WorkoutExercise(exerciseName: name, muscleGroups: ["General"], order: order)
        exercise.supersetId = superset
        exercise.supersetOrder = position
        exercise.sets = [
            WorkoutSet(plannedReps: 10, actualReps: 10, plannedWeight: 40, actualWeight: 40, restTime: 60, order: 0),
            WorkoutSet(plannedReps: 8, actualReps: 8, plannedWeight: 40, actualWeight: 40, restTime: 60, order: 1),
        ]
        exercise.workoutSession = session
        return exercise
    }
}
