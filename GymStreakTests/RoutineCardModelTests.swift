//
//  RoutineCardModelTests.swift
//  GymStreakTests
//
//  Pins the precomputed routine card models that replaced the four per-render graph
//  walks `RoutineCardView` used to do (docs/history-performance.md, "Routinen tab").
//  Two things have to stay true: the single-pass builder must agree with the metric
//  functions it replaced, and the ViewModel must rebuild the cards on every mutation —
//  precomputing removed the SwiftData observation the cards used to get for free.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

/// Catalog sync is irrelevant to these tests; the real requester is not.
@MainActor
private final class NoopCatalogSyncRequester: ExerciseCatalogSyncRequesting {
    func requestCatalogSync() {}
}

@Suite(.serialized)
@MainActor
struct RoutineCardModelTests {

    // MARK: - Fixtures

    private func makeRoutine(exerciseCount: Int, setsPerExercise: Int) -> Routine {
        let routine = Routine(name: "Push Day")
        for index in 0..<exerciseCount {
            let exercise = Exercise(
                name: "Exercise \(index)",
                muscleGroups: ["Muscle \(index)"],
                equipmentType: index.isMultiple(of: 2) ? .barbell : .dumbbell
            )
            let entry = RoutineExercise(exercise: exercise, order: index)
            entry.sets = (0..<setsPerExercise).map {
                ExerciseSet(reps: 8, weight: 60, restTime: 90, order: $0)
            }
            routine.routineExercises?.append(entry)
        }
        return routine
    }

    private func makeViewModel() -> (viewModel: RoutinesViewModel, context: ModelContext) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let viewModel = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .free),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )
        return (viewModel, context)
    }

    // MARK: - Builder parity

    @Test("The single-pass builder reports what the three metric functions reported")
    func cardModelAgreesWithTheMetricFunctionsItReplaced() {
        let routine = makeRoutine(exerciseCount: 5, setsPerExercise: 3)

        let card = RoutineMetricsService.cardModel(for: routine, nextDue: nil, lastPerformed: nil)

        #expect(card.setCount == RoutineMetricsService.totalSets(for: routine))
        #expect(card.estimatedDurationMinutes == RoutineMetricsService.estimatedDurationMinutes(for: routine))
        #expect(
            card.muscleGroups
                == Array(RoutineMetricsService.primaryMuscleGroups(for: routine).prefix(3))
        )
        #expect(card.exerciseCount == routine.routineExercisesList.count)
        #expect(card.name == routine.name)
    }

    @Test("An empty routine still reports the one-minute floor rather than zero")
    func emptyRoutineKeepsTheDurationFloor() {
        let routine = Routine(name: "Empty")

        let card = RoutineMetricsService.cardModel(for: routine, nextDue: nil, lastPerformed: nil)

        #expect(card.exerciseCount == 0)
        #expect(card.setCount == 0)
        #expect(card.estimatedDurationMinutes == RoutineMetricsService.estimatedDurationMinutes(for: routine))
        #expect(card.avatars.isEmpty)
        #expect(card.muscleGroups.isEmpty)
    }

    @Test("Avatars are the first three exercises in order, carrying their own values")
    func avatarsFollowExerciseOrderAndCarryDisplayValues() {
        let routine = makeRoutine(exerciseCount: 6, setsPerExercise: 1)
        // Insertion order is deliberately not display order.
        routine.routineExercises?.reverse()
        let ordered = routine.routineExercisesList.sorted { $0.order < $1.order }

        let card = RoutineMetricsService.cardModel(for: routine, nextDue: nil, lastPerformed: nil)

        #expect(card.avatars.count == 3)
        #expect(card.avatars.map(\.id) == ordered.prefix(3).map(\.id))
        #expect(card.avatars.first?.equipmentType == ordered.first?.exercise?.equipmentType)
        #expect(card.avatars.first?.muscleGroups == ordered.first?.exercise?.muscleGroups)
        #expect(card.muscleGroups.count == 3)
    }

    @Test("An exercise whose library entry is gone still gets a renderable avatar")
    func missingExerciseFallsBackInsteadOfDroppingTheAvatar() {
        let routine = Routine(name: "Stranded")
        routine.routineExercises = [RoutineExercise(order: 0)]

        let card = RoutineMetricsService.cardModel(for: routine, nextDue: nil, lastPerformed: nil)

        #expect(card.avatars.count == 1)
        #expect(card.avatars.first?.muscleGroups == ["General"])
        #expect(card.avatars.first?.equipmentType == .dumbbell)
    }

    // MARK: - ViewModel precomputation

    @Test("The hero is published as a card and excluded from the rest, with its own id")
    func heroCardIsExcludedFromTheOtherCards() throws {
        let (viewModel, context) = makeViewModel()
        let repository = SwiftDataRoutineRepository(modelContext: context)

        let trainedRecently = Routine(name: "Push Day")
        let trainedLongAgo = Routine(name: "Pull Day")
        repository.insert(trainedRecently)
        repository.insert(trainedLongAgo)

        let recent = WorkoutSession(routine: trainedRecently)
        recent.startTime = Date(timeIntervalSince1970: 9_000)
        recent.endTime = Date(timeIntervalSince1970: 9_500)
        let old = WorkoutSession(routine: trainedLongAgo)
        old.startTime = Date(timeIntervalSince1970: 1_000)
        old.endTime = Date(timeIntervalSince1970: 1_500)
        context.insert(recent)
        context.insert(old)
        try context.save()

        viewModel.fetchRoutines()

        // Least-recently-trained wins when nothing is planned.
        #expect(viewModel.heroCard?.id == trainedLongAgo.id)
        #expect(viewModel.otherCards.map(\.id) == [trainedRecently.id])
        #expect(viewModel.heroCard?.lastPerformed == old.startTime)
        #expect(viewModel.otherCards.first?.lastPerformed == recent.startTime)
        #expect(viewModel.mostRecentTraining == recent.startTime)
    }

    @Test("Editing a routine's sets rebuilds its card instead of leaving a stale count")
    func mutatingSetsRebuildsTheCard() throws {
        let (viewModel, context) = makeViewModel()
        let repository = SwiftDataRoutineRepository(modelContext: context)

        let routine = makeRoutine(exerciseCount: 1, setsPerExercise: 2)
        repository.insert(routine)
        viewModel.fetchRoutines()

        #expect(viewModel.heroCard?.setCount == 2)

        let entry = try #require(routine.routineExercisesList.first)
        _ = viewModel.addSet(to: entry)

        // The card no longer reads the @Model, so only an explicit rebuild can
        // move this number — that is the regression this test exists for.
        #expect(viewModel.heroCard?.setCount == 3)
    }

    @Test("Deleting an exercise refreshes the routine cards that used it")
    func deletingAnExerciseRefreshesTheRoutineCards() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let viewModel = RoutinesViewModel(
            routineRepository: routineRepository,
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .free),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )
        let exercisesViewModel = ExercisesViewModel(
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            routineRepository: routineRepository,
            catalogSync: NoopCatalogSyncRequester()
        )

        let exercise = Exercise(name: "Bench Press", muscleGroups: ["Chest"])
        context.insert(exercise)
        let routine = Routine(name: "Push Day")
        let entry = RoutineExercise(exercise: exercise, order: 0)
        entry.sets = [ExerciseSet(reps: 8, weight: 60, restTime: 90, order: 0)]
        routine.routineExercises = [entry]
        routineRepository.insert(routine)
        try context.save()

        viewModel.fetchRoutines()
        #expect(viewModel.heroCard?.exerciseCount == 1)

        // Deletes the RoutineExercise rows too — the routine template really changed,
        // on a screen that never touches a routine directly.
        exercisesViewModel.requestDeleteExercise(exercise)
        await exercisesViewModel.confirmDeleteExercise()

        // The refresh arrives through `.routineTemplateDidChange`, so it is a main-queue
        // hop rather than a direct call.
        for _ in 0..<100 where viewModel.heroCard?.exerciseCount != 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.heroCard?.exerciseCount == 0)
        #expect(viewModel.heroCard?.avatars.isEmpty == true)
    }

    @Test("Renaming a routine rebuilds its card")
    func renamingRebuildsTheCard() {
        let (viewModel, context) = makeViewModel()
        let repository = SwiftDataRoutineRepository(modelContext: context)

        let routine = Routine(name: "Old Name")
        repository.insert(routine)
        viewModel.fetchRoutines()
        #expect(viewModel.heroCard?.name == "Old Name")

        routine.name = "New Name"
        viewModel.updateRoutine(routine)

        #expect(viewModel.heroCard?.name == "New Name")
    }
}
