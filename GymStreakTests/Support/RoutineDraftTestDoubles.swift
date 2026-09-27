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
import SwiftData
import Testing
@testable import GymStreak

/// A `RoutineDrafting` that replays a scripted stream. Setting `failure` makes the
/// stream throw after whatever snapshots were scripted, which is the shape a real
/// generation failure has.
@MainActor
final class FakeRoutineDrafting: RoutineDrafting {

    /// What every turn streams, unless `answerSnapshots` scripts the answer turns.
    var snapshots: [RoutineDraftSnapshot] = []
    /// One scripted stream per answer turn, consumed in order. When it runs out, an
    /// answer turn streams `snapshots`.
    var answerSnapshots: [[RoutineDraftSnapshot]] = []
    var failure: Error?

    private(set) var prewarmCount = 0
    private(set) var requestedDescriptions: [String] = []
    private(set) var requestedUnits: [WeightUnit] = []
    private(set) var answers: [(text: String, gap: RoutineDraftGap)] = []

    /// Every model turn this double was asked for: descriptions plus answers.
    var turnCount: Int { requestedDescriptions.count + answers.count }

    func prewarm() { prewarmCount += 1 }

    func draft(
        from description: String,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        requestedDescriptions.append(description)
        requestedUnits.append(weightUnit)
        return stream(snapshots)
    }

    func answer(
        _ answer: String,
        to gap: RoutineDraftGap,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        answers.append((answer, gap))
        requestedUnits.append(weightUnit)
        let scripted = answerSnapshots.isEmpty ? snapshots : answerSnapshots.removeFirst()
        return stream(scripted)
    }

    private func stream(_ scripted: [RoutineDraftSnapshot]) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
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

// MARK: - Fixtures

/// Real `Exercise` models — `ExerciseNameResolver` matches on the stored `name`, so a
/// stand-in would not exercise the folding it does.
@MainActor
func routineDraftLibrary(_ names: [String]) -> [Exercise] {
    let context = ModelContext(InMemoryModelContainer.make())
    return names.map { name in
        let exercise = Exercise(name: name)
        context.insert(exercise)
        return exercise
    }
}

func routineDraftEntry(
    _ name: String,
    sets: Int = 3,
    reps: Int = 8,
    weight: Double = 60,
    repRange: (low: Int, high: Int) = (0, 0),
    rest: (unit: RoutineDraftEntry.RestUnit, amount: Double) = (.unstated, 0)
) -> RoutineDraftEntry {
    RoutineDraftEntry(
        name: name,
        setCount: sets,
        reps: reps,
        weight: weight,
        // The span the model copies; a zero end means it copied nothing.
        repRange: repRange.low > 0 && repRange.high > 0 ? "\(repRange.low)-\(repRange.high)" : "",
        restUnit: rest.unit,
        restAmount: rest.amount
    )
}

func routineDraftSnapshot(
    name: String = "Push Day",
    _ entries: [RoutineDraftEntry]
) -> RoutineDraftSnapshot {
    RoutineDraftSnapshot(name: name, exercises: entries)
}

// MARK: - Harness

/// The drafting sheet's ViewModel with every collaborator faked: a scripted stream, a
/// recording creation seam, a spying allowance store and a stubbed device.
///
/// Shared by `RoutineDraftTests` (the tracer bullet) and `RoutineDraftResolutionTests`
/// (resolving unmatched and ambiguous names) so the two read the same setup.
@MainActor
struct RoutineDraftHarness {

    let viewModel: RoutineDraftViewModel
    let gate: AICoachAllowanceGate
    let drafting: FakeRoutineDrafting
    let routines: FakeRoutineCreating
    let paywalls: RecordingPaywallPresenter
    let allowance: SpyAllowanceStore
    let exercises: FakeExerciseRepository

    static func make(
        state: ProEntitlementState = .free,
        availability: AICoachAvailabilityState = .available,
        libraryNames: [String] = ["Bench Press", "Row", "Squat", "Bankdrücken"]
    ) -> RoutineDraftHarness {
        let paywalls = RecordingPaywallPresenter()
        let allowance = SpyAllowanceStore()
        let availabilityStub = StubAICoachAvailability(state: availability)
        let gate = AICoachAllowanceGate(
            surface: .coachChat,
            entitlements: StubProEntitlements(state: state),
            paywalls: paywalls,
            allowance: allowance,
            availability: availabilityStub,
            isGatingEnabled: true
        )
        let drafting = FakeRoutineDrafting()
        let routines = FakeRoutineCreating()
        let exercises = FakeExerciseRepository(exercises: routineDraftLibrary(libraryNames))
        return RoutineDraftHarness(
            viewModel: RoutineDraftViewModel(
                allowanceGate: gate,
                drafting: drafting,
                exerciseRepository: exercises,
                routines: routines,
                paywalls: paywalls,
                availability: availabilityStub
            ),
            gate: gate,
            drafting: drafting,
            routines: routines,
            paywalls: paywalls,
            allowance: allowance,
            exercises: exercises
        )
    }

    /// Lets the scripted stream drain. The fake yields into an unbounded buffer and
    /// finishes synchronously, so this settles in a handful of turns; the bound only stops
    /// a bug from hanging the suite.
    func settle(turns: Int = 500) async {
        for _ in 0..<turns {
            if !viewModel.isDrafting { return }
            await Task.yield()
        }
        Issue.record("the draft never finished")
    }
}
