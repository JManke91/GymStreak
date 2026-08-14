//
//  RoutineTemplateSyncServiceTests.swift
//  GymStreakTests
//
//  The `reconcileExerciseMembership: false` half of the template writeback —
//  the path a past-workout edit takes (`WorkoutViewModel.saveEditedWorkout` →
//  `EditWorkoutSessionView`). Audit P1.5 moved this logic out of
//  `WorkoutViewModel`, and an audit of the regression net found it had **no**
//  coverage at all: every existing template test goes through
//  `completeWorkout(updateTemplate:)`, which is the `true` branch.
//
//  What makes the `false` branch its own risk: it must never add or remove
//  routine slots (the routine may have changed since that older workout was
//  recorded), and it is the only caller that enables the legacy fallback in
//  `matchingRoutineExercise` for history recorded before slot ids existed.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineTemplateSyncServiceTests {
    private struct Fixture {
        let context: ModelContext
        let routineRepository: SwiftDataRoutineRepository
        let service: RoutineTemplateSyncService
    }

    private func makeFixture() -> Fixture {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        return Fixture(
            context: context,
            routineRepository: routineRepository,
            service: RoutineTemplateSyncService(
                routineRepository: routineRepository,
                exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
            )
        )
    }

    /// A routine with one slot holding one set, plus a session performing it.
    /// `linkSlotId` off produces legacy history (no `routineExerciseId`), which
    /// is what the name/id fallback exists for.
    private func makeScenario(
        _ fixture: Fixture,
        templateReps: Int = 8,
        templateWeight: Double = 50,
        performedReps: Int = 10,
        performedWeight: Double = 60,
        linkSlotId: Bool = true
    ) -> (routine: Routine, slot: RoutineExercise, session: WorkoutSession, workoutExercise: WorkoutExercise) {
        let exercise = Exercise(name: "Bench Press")
        fixture.context.insert(exercise)

        let routine = Routine(name: "Push")
        let slot = RoutineExercise(exercise: exercise, order: 0)
        slot.routine = routine
        routine.routineExercises = [slot]
        fixture.context.insert(slot)
        fixture.routineRepository.insert(routine)

        let templateSet = ExerciseSet(reps: templateReps, weight: templateWeight, restTime: 60, order: 0)
        fixture.context.insert(templateSet)
        templateSet.routineExercise = slot
        slot.sets = [templateSet]

        let session = WorkoutSession(routine: routine)
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: 0,
            exerciseId: exercise.id,
            routineExerciseId: linkSlotId ? slot.id : nil
        )
        workoutExercise.workoutSession = session
        session.workoutExercises = [workoutExercise]

        let performed = WorkoutSet(
            plannedReps: templateReps,
            actualReps: performedReps,
            plannedWeight: templateWeight,
            actualWeight: performedWeight,
            restTime: 90,
            order: 0
        )
        performed.isCompleted = true
        performed.workoutExercise = workoutExercise
        workoutExercise.sets = [performed]
        fixture.context.insert(session)

        return (routine, slot, session, workoutExercise)
    }

    @Test
    func historicalEditWritesPerformedValuesOntoTheMatchedSlot() throws {
        let fixture = makeFixture()
        let scenario = makeScenario(fixture)

        fixture.service.applyPerformedValues(
            from: scenario.session,
            reconcileExerciseMembership: false
        )

        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.reps == 10)
        #expect(templateSet.weight == 60)
        // Rest time reconciles from the exercise, outside the value writeback.
        #expect(templateSet.restTime == 90)
    }

    /// The defining difference from the active-workout path: a routine that has
    /// gained or lost exercises since the workout was recorded must not be
    /// restructured by editing that old workout.
    @Test
    func historicalEditNeverAddsOrRemovesRoutineSlots() throws {
        let fixture = makeFixture()
        let scenario = makeScenario(fixture)

        // A slot added to the routine after the workout was recorded.
        let laterExercise = Exercise(name: "Cable Fly")
        fixture.context.insert(laterExercise)
        let laterSlot = RoutineExercise(exercise: laterExercise, order: 1)
        laterSlot.routine = scenario.routine
        fixture.context.insert(laterSlot)
        scenario.routine.routineExercises?.append(laterSlot)

        // An exercise performed ad hoc during that workout, with no slot.
        let adHoc = WorkoutExercise(
            exerciseName: "Pec Deck",
            muscleGroups: ["Chest"],
            order: 1
        )
        adHoc.workoutSession = scenario.session
        scenario.session.workoutExercises?.append(adHoc)

        fixture.service.applyPerformedValues(
            from: scenario.session,
            reconcileExerciseMembership: false
        )

        let slots = scenario.routine.routineExercisesList.sorted { $0.order < $1.order }
        #expect(slots.map(\.id) == [scenario.slot.id, laterSlot.id])
        #expect(adHoc.routineExerciseId == nil)
    }

    /// History recorded before slot ids existed carries no `routineExerciseId`.
    /// The historical-edit path is the only one that resolves it by exercise
    /// identity instead — `completeWorkout` deliberately does not.
    @Test
    func legacyHistoryWithoutSlotIdsResolvesByExerciseIdentity() throws {
        let fixture = makeFixture()
        let scenario = makeScenario(fixture, linkSlotId: false)

        fixture.service.applyPerformedValues(
            from: scenario.session,
            reconcileExerciseMembership: false
        )

        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.reps == 10)
        #expect(templateSet.weight == 60)
    }

    /// The fallback is enabled only when *no* workout exercise carries a slot
    /// id. A session mixing linked and unlinked exercises must not have its
    /// unlinked ones guessed onto slots.
    @Test
    func mixedHistoryDisablesTheLegacyFallback() throws {
        let fixture = makeFixture()
        let scenario = makeScenario(fixture)

        // A second, unlinked workout exercise pointing at the same library
        // exercise as the (already claimed) slot.
        let unlinked = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["Chest"],
            order: 1,
            exerciseId: scenario.slot.exercise?.id
        )
        let extraSet = WorkoutSet(
            plannedReps: 5,
            actualReps: 5,
            plannedWeight: 100,
            actualWeight: 100,
            restTime: 30,
            order: 0
        )
        extraSet.isCompleted = true
        extraSet.workoutExercise = unlinked
        unlinked.sets = [extraSet]
        unlinked.workoutSession = scenario.session
        scenario.session.workoutExercises?.append(unlinked)

        fixture.service.applyPerformedValues(
            from: scenario.session,
            reconcileExerciseMembership: false
        )

        // The linked exercise won the slot; the unlinked one wrote nothing.
        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.weight == 60)
        #expect(scenario.slot.setsList.count == 1)
    }

    /// Set count still reconciles on this path even though slot membership does
    /// not — deleting a set while editing a past workout must shrink the
    /// template too.
    @Test
    func historicalEditReconcilesSetCountWithinAMatchedSlot() throws {
        let fixture = makeFixture()
        let scenario = makeScenario(fixture)

        let surplus = ExerciseSet(reps: 8, weight: 50, restTime: 60, order: 1)
        fixture.context.insert(surplus)
        surplus.routineExercise = scenario.slot
        scenario.slot.sets?.append(surplus)

        fixture.service.applyPerformedValues(
            from: scenario.session,
            reconcileExerciseMembership: false
        )

        #expect(scenario.slot.setsList.count == 1)
    }

    /// The service mutates and leaves saving to its caller — `WorkoutViewModel`
    /// commits the template write in the same `save()` as the edited session.
    @Test
    func theServiceDoesNotSave() throws {
        let fixture = makeFixture()
        let scenario = makeScenario(fixture)

        fixture.service.applyPerformedValues(
            from: scenario.session,
            reconcileExerciseMembership: false
        )

        #expect(fixture.context.hasChanges)
    }

    @Test
    func aSessionWithoutARoutineIsLeftAlone() {
        let fixture = makeFixture()
        let session = WorkoutSession(routine: nil)
        fixture.context.insert(session)

        fixture.service.applyPerformedValues(from: session, reconcileExerciseMembership: false)
        fixture.service.applyPerformedValues(from: session, reconcileExerciseMembership: true)

        #expect(session.routine == nil)
    }
}
