//
//  EditWorkoutSessionCommitTests.swift
//  GymStreakTests
//
//  `WorkoutViewModel.saveEditedWorkout(_:exerciseDrafts:updateTemplate:)` — the
//  commit half of editing a past workout (`EditWorkoutSessionView`). An audit of
//  the regression net during P1.5 found this method had **no** test anywhere in
//  the repo, despite being the only path that mutates already-recorded history.
//
//  `RoutineTemplateSyncServiceTests` covers the template writeback it delegates
//  to; this suite covers what the ViewModel itself does — draft reconciliation
//  against the persisted sets, the planned-vs-actual field choice, the
//  `didUpdateTemplate` flag, and the watch-sync notification.
//
//  Deliberately NOT covered: the two `AICoachCache` invalidations. There is no
//  `AICoachCaching` double in this target and the real `.shared` does FileManager
//  I/O in the test host — that is audit P2.6, a separate change.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct EditWorkoutSessionCommitTests {
    private final class EmptyWorkoutHistoryCorrelationProvider: WorkoutHistoryCorrelationProviding {
        func healthKitWorkoutIDs() throws -> Set<UUID> { [] }
        func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID? { nil }
    }

    private final class StubRestTimerReminders: RestTimerReminderScheduling {
        func scheduleReminder(id: UUID, deadline: Date) async -> RestTimerReminderOutcome { .scheduled }
        func cancelReminder(id: UUID) {}
    }

    private struct Fixture {
        let context: ModelContext
        let sessionRepository: SwiftDataWorkoutSessionRepository
        let routineRepository: SwiftDataRoutineRepository
        let viewModel: WorkoutViewModel
    }

    private func makeFixture() -> Fixture {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
        return Fixture(
            context: context,
            sessionRepository: sessionRepository,
            routineRepository: routineRepository,
            viewModel: WorkoutViewModel(
                workoutSessionRepository: sessionRepository,
                routineRepository: routineRepository,
                healthKitManager: MockHealthKitWorkoutServicing(),
                watchSync: MockWatchSyncServicing(),
                workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
                restTimerReminders: StubRestTimerReminders(),
                restTimerLiveActivity: RecordingRestTimerLiveActivity(),
                routineTemplateSync: RoutineTemplateSyncService(
                    routineRepository: routineRepository,
                    exerciseRepository: exerciseRepository
                )
            )
        )
    }

    /// A completed session whose single exercise has `setCount` completed sets,
    /// optionally wired to a live routine template with the same set count.
    @discardableResult
    private func makeRecordedWorkout(
        _ fixture: Fixture,
        setCount: Int = 2,
        withRoutine: Bool = true,
        overloadApplied: Bool = false
    ) -> (session: WorkoutSession, workoutExercise: WorkoutExercise, slot: RoutineExercise?) {
        var slot: RoutineExercise?
        var routine: Routine?

        if withRoutine {
            let exercise = Exercise(name: "Bench Press")
            fixture.context.insert(exercise)
            let newRoutine = Routine(name: "Push")
            let newSlot = RoutineExercise(exercise: exercise, order: 0)
            newSlot.routine = newRoutine
            newRoutine.routineExercises = [newSlot]
            fixture.context.insert(newSlot)
            fixture.routineRepository.insert(newRoutine)
            for order in 0..<setCount {
                let templateSet = ExerciseSet(reps: 8, weight: 50, restTime: 60, order: order)
                fixture.context.insert(templateSet)
                templateSet.routineExercise = newSlot
                newSlot.sets = (newSlot.sets ?? []) + [templateSet]
            }
            slot = newSlot
            routine = newRoutine
        }

        let session = WorkoutSession(routine: routine)
        session.endTime = session.startTime.addingTimeInterval(3_600)
        let workoutExercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["Chest"],
            order: 0,
            routineExerciseId: slot?.id
        )
        workoutExercise.progressiveOverloadApplied = overloadApplied
        workoutExercise.workoutSession = session

        var sets: [WorkoutSet] = []
        for order in 0..<setCount {
            let set = WorkoutSet(
                plannedReps: 8,
                actualReps: 10,
                plannedWeight: 50,
                actualWeight: 60,
                restTime: 60,
                order: order
            )
            set.isCompleted = true
            set.completedAt = session.endTime
            set.workoutExercise = workoutExercise
            sets.append(set)
        }
        workoutExercise.sets = sets
        session.workoutExercises = [workoutExercise]
        fixture.sessionRepository.insert(session)

        return (session, workoutExercise, slot)
    }

    private func draft(
        for workoutExercise: WorkoutExercise,
        usePlanned: Bool = false,
        sets: [WorkoutSetDraft]
    ) -> WorkoutExerciseDraft {
        WorkoutExerciseDraft(
            id: workoutExercise.id,
            name: workoutExercise.exerciseName,
            usePlanned: usePlanned,
            sets: sets
        )
    }

    private func keptSet(
        _ set: WorkoutSet,
        reps: Int,
        weight: Double,
        restTime: TimeInterval = 60,
        isCompleted: Bool = true
    ) -> WorkoutSetDraft {
        WorkoutSetDraft(
            id: UUID(),
            existingSetId: set.id,
            reps: reps,
            weight: weight,
            restTime: restTime,
            isCompleted: isCompleted
        )
    }

    private func addedSet(
        reps: Int,
        weight: Double,
        restTime: TimeInterval = 60,
        isCompleted: Bool = true
    ) -> WorkoutSetDraft {
        WorkoutSetDraft(
            id: UUID(),
            existingSetId: nil,
            reps: reps,
            weight: weight,
            restTime: restTime,
            isCompleted: isCompleted
        )
    }

    // MARK: - Draft reconciliation

    @Test
    func editingAKeptSetWritesTheActualFields() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [draft(for: recorded.workoutExercise, sets: [keptSet(original, reps: 12, weight: 65)])],
            updateTemplate: false
        )

        #expect(original.actualReps == 12)
        #expect(original.actualWeight == 65)
        // Planned values are the record of what was prescribed — untouched.
        #expect(original.plannedReps == 8)
        #expect(original.plannedWeight == 50)
    }

    /// An overload-applied exercise displays (and therefore edits) the planned
    /// fields, mirroring `WorkoutDetailExerciseBlock`.
    @Test
    func editingWithUsePlannedWritesThePlannedFieldsInstead() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1, overloadApplied: true)
        let original = try #require(recorded.workoutExercise.setsList.first)

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [
                draft(
                    for: recorded.workoutExercise,
                    usePlanned: true,
                    sets: [keptSet(original, reps: 6, weight: 70)]
                )
            ],
            updateTemplate: false
        )

        #expect(original.plannedReps == 6)
        #expect(original.plannedWeight == 70)
        #expect(original.actualReps == 10)
        #expect(original.actualWeight == 60)
    }

    @Test
    func aSetDroppedFromTheDraftIsDeleted() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 2)
        let sets = recorded.workoutExercise.setsList.sorted { $0.order < $1.order }
        let kept = try #require(sets.first)

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [draft(for: recorded.workoutExercise, sets: [keptSet(kept, reps: 10, weight: 60)])],
            updateTemplate: false
        )

        #expect(recorded.workoutExercise.setsList.map(\.id) == [kept.id])
        let remaining = try fixture.context.fetch(FetchDescriptor<WorkoutSet>())
        #expect(remaining.count == 1)
    }

    @Test
    func aSetAddedInTheEditorIsInsertedInDraftOrder() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [
                draft(
                    for: recorded.workoutExercise,
                    sets: [
                        keptSet(original, reps: 10, weight: 60),
                        addedSet(reps: 8, weight: 55, restTime: 90)
                    ]
                )
            ],
            updateTemplate: false
        )

        let sets = recorded.workoutExercise.setsList.sorted { $0.order < $1.order }
        #expect(sets.count == 2)
        #expect(sets.map(\.order) == [0, 1])
        let added = try #require(sets.last)
        #expect(added.actualReps == 8)
        #expect(added.actualWeight == 55)
        // A newly added set seeds both fields, so aggregators reading either agree.
        #expect(added.plannedReps == 8)
        #expect(added.plannedWeight == 55)
        #expect(added.restTime == 90)
        #expect(added.isCompleted)
        #expect(added.completedAt == recorded.session.endTime)
    }

    @Test
    func unmarkingASetAsCompletedClearsItsTimestamp() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)
        #expect(original.completedAt != nil)

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [
                draft(
                    for: recorded.workoutExercise,
                    sets: [keptSet(original, reps: 10, weight: 60, isCompleted: false)]
                )
            ],
            updateTemplate: false
        )

        #expect(original.isCompleted == false)
        #expect(original.completedAt == nil)
    }

    /// The draft carries a `WorkoutExercise.id`; one that matches nothing in the
    /// session must be skipped rather than throwing off the other drafts.
    @Test
    func aDraftForAnUnknownExerciseIsIgnored() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)

        let orphanDraft = WorkoutExerciseDraft(
            id: UUID(),
            name: "Ghost",
            usePlanned: false,
            sets: [addedSet(reps: 1, weight: 1)]
        )

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [orphanDraft, draft(for: recorded.workoutExercise, sets: [keptSet(original, reps: 11, weight: 61)])],
            updateTemplate: false
        )

        #expect(original.actualReps == 11)
        #expect(recorded.session.workoutExercisesList.count == 1)
        #expect(recorded.workoutExercise.setsList.count == 1)
    }

    // MARK: - Template propagation

    @Test
    func updatingTheTemplatePushesTheEditedValuesOntoTheRoutineAndNotifiesTheWatch() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)
        let slot = try #require(recorded.slot)

        var notified = false
        let observer = NotificationCenter.default.addObserver(
            forName: .routineTemplateDidChange,
            object: nil,
            queue: .main
        ) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [draft(for: recorded.workoutExercise, sets: [keptSet(original, reps: 12, weight: 65)])],
            updateTemplate: true
        )

        let templateSet = try #require(slot.setsList.first)
        #expect(templateSet.reps == 12)
        #expect(templateSet.weight == 65)
        #expect(recorded.session.didUpdateTemplate)
        #expect(notified)
    }

    @Test
    func decliningTheTemplateUpdateLeavesTheRoutineAloneAndSendsNoNotification() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)
        let slot = try #require(recorded.slot)

        var notified = false
        let observer = NotificationCenter.default.addObserver(
            forName: .routineTemplateDidChange,
            object: nil,
            queue: .main
        ) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [draft(for: recorded.workoutExercise, sets: [keptSet(original, reps: 12, weight: 65)])],
            updateTemplate: false
        )

        let templateSet = try #require(slot.setsList.first)
        #expect(templateSet.reps == 8)
        #expect(templateSet.weight == 50)
        #expect(recorded.session.didUpdateTemplate == false)
        #expect(notified == false)
    }

    /// Regression for a latent bug the P1.5 extraction exposed: the template
    /// writeback used to own the only `save()` on the `updateTemplate == true`
    /// branch, and it returns early for a session with no routine — so ticking
    /// "update routine" on a routine-less workout silently dropped the user's set
    /// edits. The save is now unconditional.
    @Test
    func editsToARoutinelessWorkoutSurviveEvenWhenTemplateUpdateIsRequested() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1, withRoutine: false)
        let original = try #require(recorded.workoutExercise.setsList.first)
        #expect(recorded.session.routine == nil)

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [draft(for: recorded.workoutExercise, sets: [keptSet(original, reps: 15, weight: 80)])],
            updateTemplate: true
        )

        #expect(original.actualReps == 15)
        #expect(original.actualWeight == 80)
        // Committed, not merely mutated in memory.
        #expect(fixture.context.hasChanges == false)
        let persisted = try #require(
            fixture.sessionRepository.findSession(id: recorded.session.id, healthKitWorkoutId: nil)
        )
        let persistedSet = try #require(persisted.workoutExercisesList.first?.setsList.first)
        #expect(persistedSet.actualReps == 15)
    }

    @Test
    func committingAnEditAdvancesTheHistoryInvalidationToken() throws {
        let fixture = makeFixture()
        let recorded = makeRecordedWorkout(fixture, setCount: 1)
        let original = try #require(recorded.workoutExercise.setsList.first)
        let before = fixture.viewModel.historyVersion

        fixture.viewModel.saveEditedWorkout(
            recorded.session,
            exerciseDrafts: [draft(for: recorded.workoutExercise, sets: [keptSet(original, reps: 9, weight: 55)])],
            updateTemplate: false
        )

        #expect(fixture.viewModel.historyVersion != before)
    }
}
