//
//  RoutineDraftTestDoubles.swift
//  GymStreakTests
//
//  Doubles for the AI routine-drafting surface (docs/ai-coach-routine-drafting.md).
//
//  The drafting double is the reason `RoutineDrafting` hands out an
//  `AsyncThrowingStream` instead of a `LanguageModelSession.ResponseStream`: the
//  framework stream has no public initializer, so no test could produce one carrying
//  content — and the acceptance criteria here are about what happens *while* and *after*
//  a draft streams.
//

import Foundation
@testable import GymStreak

/// A `RoutineDrafting` that replays a scripted stream. Setting `failure` makes the
/// stream throw after whatever snapshots were scripted, which is the shape a real
/// generation failure has.
@MainActor
final class FakeRoutineDrafting: RoutineDrafting {

    var snapshots: [RoutineDraftSnapshot] = []
    var failure: Error?

    private(set) var prewarmCount = 0
    private(set) var requestedDescriptions: [String] = []
    private(set) var requestedUnits: [WeightUnit] = []

    func prewarm() { prewarmCount += 1 }

    func draft(
        from description: String,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        requestedDescriptions.append(description)
        requestedUnits.append(weightUnit)
        let scripted = snapshots
        let thrown = failure
        return AsyncThrowingStream { continuation in
            for snapshot in scripted { continuation.yield(snapshot) }
            if let thrown {
                continuation.finish(throwing: thrown)
            } else {
                continuation.finish()
            }
        }
    }
}

/// A `RoutineCreating` that records the transaction instead of performing it. Standing
/// in for `RoutinesViewModel`, whose real `createRoutine` needs a `ModelContext`.
@MainActor
final class FakeRoutineCreating: RoutineCreating {

    var isRoutineCapReached = false

    private(set) var createdNames: [String] = []
    private(set) var createdExercises: [[PendingRoutineExercise]] = []

    var createCount: Int { createdNames.count }

    func createRoutine(name: String, pendingExercises: [PendingRoutineExercise]) {
        createdNames.append(name)
        createdExercises.append(pendingExercises)
    }
}

/// An in-memory `ExerciseRepository` over exercises a test built itself.
@MainActor
final class FakeExerciseRepository: ExerciseRepository {

    var exercises: [Exercise] = []
    private(set) var fetchAllCount = 0

    init(exercises: [Exercise] = []) {
        self.exercises = exercises
    }

    func fetchAll() -> [Exercise] {
        fetchAllCount += 1
        return exercises
    }

    func fetch(id: UUID) -> Exercise? { exercises.first { $0.id == id } }

    func fetchBySeedKey(_ seedKey: String) -> [Exercise] {
        guard !seedKey.isEmpty else { return [] }
        return exercises.filter { $0.seedKey == seedKey }
    }

    func insert(_ exercise: Exercise) { exercises.append(exercise) }

    func delete(_ exercise: Exercise) { exercises.removeAll { $0.id == exercise.id } }

    func save() throws {}
}

/// The error a scripted generation failure throws. A plain value: what matters to the
/// ViewModel is that the stream threw, not which framework case it threw.
struct RoutineDraftTestFailure: Error {}
