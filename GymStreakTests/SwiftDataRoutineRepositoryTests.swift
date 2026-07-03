//
//  SwiftDataRoutineRepositoryTests.swift
//  GymStreakTests
//
//  Covers SwiftDataRoutineRepository against an in-memory SwiftData store:
//  sort order, id lookup, insert/delete round-trip, and cascade-delete of
//  child RoutineExercise/ExerciseSet records.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// Serialized: each test creates its own in-memory ModelContainer, and SwiftData's
// schema initialization is not safe to run concurrently across containers within
// the same process (observed crashes in InMemoryModelContainer.make() when
// multiple suites created containers in parallel).
@Suite(.serialized)
@MainActor
struct SwiftDataRoutineRepositoryTests {

    private func makeRepository() -> (context: ModelContext, repository: SwiftDataRoutineRepository) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        return (context, SwiftDataRoutineRepository(modelContext: context))
    }

    @Test
    func fetchAllSortsByMostRecentlyUpdatedFirst() throws {
        let (_, repository) = makeRepository()

        let older = Routine(name: "Older")
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = Routine(name: "Newer")
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        // Insert in an order that would fail the assertion below if sorting
        // fell back to insertion order instead of `updatedAt`.
        repository.insert(older)
        repository.insert(newer)
        try repository.save()

        let all = repository.fetchAll()
        #expect(all.map(\.name) == ["Newer", "Older"])
    }

    @Test
    func fetchByIdReturnsMatchingRoutine() throws {
        let (_, repository) = makeRepository()
        let routine = Routine(name: "Push Day")
        repository.insert(routine)
        try repository.save()

        let fetched = repository.fetch(id: routine.id)
        #expect(fetched?.id == routine.id)
        #expect(fetched?.name == "Push Day")
    }

    @Test
    func fetchByIdReturnsNilWhenMissing() {
        let (_, repository) = makeRepository()
        #expect(repository.fetch(id: UUID()) == nil)
    }

    @Test
    func insertAndDeleteRoundTrip() throws {
        let (_, repository) = makeRepository()
        let routine = Routine(name: "Leg Day")

        repository.insert(routine)
        try repository.save()
        #expect(repository.fetch(id: routine.id) != nil)

        repository.delete(routine)
        try repository.save()
        #expect(repository.fetch(id: routine.id) == nil)
    }

    @Test
    func deletingRoutineCascadesToChildExercisesAndSets() throws {
        let (context, repository) = makeRepository()

        let exercise = Exercise(name: "Bench Press")
        let routine = Routine(name: "Push Day")
        let routineExercise = RoutineExercise(exercise: exercise, order: 0)
        routineExercise.routine = routine
        let set = ExerciseSet(reps: 8, weight: 60, restTime: 90, order: 0)
        set.routineExercise = routineExercise
        routineExercise.sets = [set]
        routine.routineExercises = [routineExercise]

        repository.insert(routine)
        try repository.save()

        let routineExerciseId = routineExercise.id
        let setId = set.id

        repository.delete(routine)
        try repository.save()

        let remainingExercises = try context.fetch(
            FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.id == routineExerciseId })
        )
        let remainingSets = try context.fetch(
            FetchDescriptor<ExerciseSet>(predicate: #Predicate { $0.id == setId })
        )

        #expect(remainingExercises.isEmpty)
        #expect(remainingSets.isEmpty)
    }
}
