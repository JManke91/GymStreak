//
//  WorkoutViewModelTests.swift
//  GymStreakTests
//
//  Covers workout occurrence identity across iPhone creation and swaps.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutViewModelTests {
    private final class EmptyWorkoutHistoryCorrelationProvider: WorkoutHistoryCorrelationProviding {
        func healthKitWorkoutIDs() throws -> Set<UUID> { [] }
        func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID? { nil }
    }

    private final class RecordingRestTimerReminders: RestTimerReminderScheduling {
        private(set) var scheduledReminders: [(id: UUID, deadline: Date)] = []
        private(set) var cancelledIDs: [UUID] = []
        var outcome: RestTimerReminderOutcome = .scheduled

        func scheduleReminder(
            id: UUID,
            deadline: Date
        ) async -> RestTimerReminderOutcome {
            scheduledReminders.append((id, deadline))
            return outcome
        }

        func cancelReminder(id: UUID) {
            cancelledIDs.append(id)
        }
    }

    @Test
    func restTimerRemindersAreDeferredUntilTimerStarts() async {
        let context = ModelContext(InMemoryModelContainer.make())
        let reminders = RecordingRestTimerReminders()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = WorkoutViewModel(
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: reminders,
            now: { now }
        )

        #expect(reminders.scheduledReminders.isEmpty)
        #expect(reminders.cancelledIDs.isEmpty)

        viewModel.startRestTimer(duration: 60)
        await Task.yield()
        let scheduledReminder = reminders.scheduledReminders.first
        #expect(reminders.scheduledReminders.count == 1)
        #expect(scheduledReminder?.deadline == now.addingTimeInterval(60))
        #expect(viewModel.restTimerReminderOutcome == .scheduled)

        viewModel.stopRestTimer()
        #expect(reminders.cancelledIDs == [scheduledReminder?.id].compactMap { $0 })
    }

    @Test
    func deniedRestTimerReminderIsExposedAsWarning() async {
        let context = ModelContext(InMemoryModelContainer.make())
        let reminders = RecordingRestTimerReminders()
        reminders.outcome = .authorizationDenied
        let viewModel = WorkoutViewModel(
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: reminders
        )

        viewModel.startRestTimer(duration: 60)
        await Task.yield()

        #expect(viewModel.restTimerReminderWarning != nil)
        viewModel.stopRestTimer()
    }

    @Test
    func restoringRestTimerDerivesRemainingTimeFromPersistedDeadline() {
        let context = ModelContext(InMemoryModelContainer.make())
        var currentDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = WorkoutViewModel(
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: RecordingRestTimerReminders(),
            now: { currentDate }
        )

        viewModel.startRestTimer(duration: 60)
        currentDate = currentDate.addingTimeInterval(25)
        viewModel.restoreTimerState()

        #expect(viewModel.restTimeRemaining == 35)
        viewModel.stopRestTimer()
    }

    @Test
    func routineWorkoutSnapshotsSlotWhileAdHocExerciseDoesNot() {
        let exercise = Exercise(name: "Biceps Curls")
        let routineExercise = RoutineExercise(exercise: exercise, order: 0)

        let planned = WorkoutExercise(from: routineExercise, order: 0)
        let adHoc = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: 0,
            exerciseId: exercise.id
        )

        #expect(planned.routineExerciseId == routineExercise.id)
        #expect(adHoc.routineExerciseId == nil)
    }

    @Test
    func swapAndRevertPreserveSlotAndSnapshotPerformedLoadBehavior() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
        let primary = Exercise(name: "Chin Up", loadBehavior: .resistance)
        let alternative = Exercise(
            name: "Assisted Chin Up",
            loadBehavior: .counterweightAssistance
        )
        let routine = Routine(name: "Pull")
        let slot = RoutineExercise(exercise: primary, order: 0)
        slot.routine = routine
        routine.routineExercises = [slot]

        let primarySet = ExerciseSet(reps: 6, weight: 0, restTime: 60)
        primarySet.routineExercise = slot
        slot.sets = [primarySet]

        let alternativeUse = RoutineExerciseAlternative(exercise: alternative, order: 0)
        alternativeUse.routineExercise = slot
        let alternativeSet = AlternativeExerciseSet(reps: 8, weight: 20, restTime: 60)
        alternativeSet.alternative = alternativeUse
        alternativeUse.sets = [alternativeSet]
        slot.alternatives = [alternativeUse]

        context.insert(primary)
        context.insert(alternative)
        context.insert(slot)
        context.insert(primarySet)
        context.insert(alternativeUse)
        context.insert(alternativeSet)
        routineRepository.insert(routine)

        let session = WorkoutSession(routine: routine)
        let workoutExercise = WorkoutExercise(from: slot, order: 0)
        workoutExercise.workoutSession = session
        session.workoutExercises = [workoutExercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        let viewModel = WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: RecordingRestTimerReminders()
        )
        viewModel.currentSession = session

        let alternativeTarget = try #require(
            viewModel.swapTargets(for: workoutExercise).first { $0.exercise.id == alternative.id }
        )
        viewModel.swapExercise(workoutExercise, to: alternativeTarget)

        #expect(workoutExercise.routineExerciseId == slot.id)
        #expect(workoutExercise.exerciseId == alternative.id)
        #expect(workoutExercise.loadBehavior == .counterweightAssistance)

        let revertTarget = try #require(
            viewModel.swapTargets(for: workoutExercise).first { $0.isOriginal }
        )
        viewModel.swapExercise(workoutExercise, to: revertTarget)

        #expect(workoutExercise.routineExerciseId == slot.id)
        #expect(workoutExercise.exerciseId == primary.id)
        #expect(workoutExercise.loadBehavior == .resistance)
    }

    @Test
    func completingWorkoutWithTemplateUpdateReplacesRemovedSlotWhenSameExerciseIsReadded() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)

        let addedExercise = Exercise(name: "Cable Fly", muscleGroups: ["Chest"])
        let routine = Routine(name: "Push")
        let removedSlot = RoutineExercise(exercise: addedExercise, order: 0)
        removedSlot.routine = routine
        routine.routineExercises = [removedSlot]
        context.insert(addedExercise)
        context.insert(removedSlot)
        routineRepository.insert(routine)

        let session = WorkoutSession(routine: routine)
        let addedWorkoutExercise = WorkoutExercise(
            exerciseName: addedExercise.name,
            muscleGroups: addedExercise.muscleGroups,
            order: 0,
            exerciseId: addedExercise.id,
            loadBehavior: addedExercise.loadBehavior
        )
        addedWorkoutExercise.workoutSession = session
        let addedWorkoutSet = WorkoutSet(
            plannedReps: 12,
            actualReps: 12,
            plannedWeight: 25,
            actualWeight: 25,
            restTime: 90,
            order: 0
        )
        addedWorkoutSet.workoutExercise = addedWorkoutExercise
        addedWorkoutExercise.sets = [addedWorkoutSet]
        session.workoutExercises = [addedWorkoutExercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        let viewModel = WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: RecordingRestTimerReminders()
        )
        viewModel.currentSession = session

        viewModel.completeWorkout(updateTemplate: true, notes: "")

        let updatedRoutine = try #require(routineRepository.fetch(id: routine.id))
        let addedSlot = try #require(
            updatedRoutine.routineExercisesList.first { $0.exercise?.id == addedExercise.id }
        )
        let addedSet = try #require(addedSlot.setsList.first)
        #expect(updatedRoutine.routineExercisesList.count == 1)
        #expect(addedSlot.id != removedSlot.id)
        #expect(addedSlot.order == 0)
        #expect(addedSet.reps == 12)
        #expect(addedSet.weight == 25)
        #expect(addedSet.restTime == 90)
        #expect(addedWorkoutExercise.routineExerciseId == addedSlot.id)
    }

    @Test
    func completingWorkoutWithTemplateUpdateRemovesMissingRoutineExercise() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)

        let firstExercise = Exercise(name: "Bench Press")
        let removedExercise = Exercise(name: "Shoulder Press")
        let lastExercise = Exercise(name: "Triceps Extension")
        let routine = Routine(name: "Push")
        let firstSlot = RoutineExercise(exercise: firstExercise, order: 0)
        let removedSlot = RoutineExercise(exercise: removedExercise, order: 1)
        let lastSlot = RoutineExercise(exercise: lastExercise, order: 2)
        for slot in [firstSlot, removedSlot, lastSlot] {
            slot.routine = routine
            context.insert(slot)
        }
        routine.routineExercises = [firstSlot, removedSlot, lastSlot]
        context.insert(firstExercise)
        context.insert(removedExercise)
        context.insert(lastExercise)
        routineRepository.insert(routine)

        let removedSet = ExerciseSet(reps: 10, weight: 20, restTime: 60)
        context.insert(removedSet)
        removedSet.routineExercise = removedSlot
        removedSlot.sets = [removedSet]

        let session = WorkoutSession(routine: routine)
        let firstWorkoutExercise = WorkoutExercise(from: firstSlot, order: 0)
        let lastWorkoutExercise = WorkoutExercise(from: lastSlot, order: 1)
        firstWorkoutExercise.workoutSession = session
        lastWorkoutExercise.workoutSession = session
        session.workoutExercises = [firstWorkoutExercise, lastWorkoutExercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        let viewModel = WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: RecordingRestTimerReminders()
        )
        viewModel.currentSession = session

        viewModel.completeWorkout(updateTemplate: true, notes: "")

        let remainingSlots = try #require(routineRepository.fetch(id: routine.id))
            .routineExercisesList
            .sorted { $0.order < $1.order }
        #expect(remainingSlots.map(\.id) == [firstSlot.id, lastSlot.id])
        #expect(remainingSlots.map(\.order) == [0, 1])
    }

    @Test
    func completingWorkoutWithoutTemplateUpdateLeavesRoutineMembershipUnchanged() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)

        let routineExercise = Exercise(name: "Bench Press")
        let addedExercise = Exercise(name: "Cable Fly")
        let routine = Routine(name: "Push")
        let slot = RoutineExercise(exercise: routineExercise, order: 0)
        slot.routine = routine
        routine.routineExercises = [slot]
        context.insert(routineExercise)
        context.insert(addedExercise)
        context.insert(slot)
        routineRepository.insert(routine)

        let session = WorkoutSession(routine: routine)
        let addedWorkoutExercise = WorkoutExercise(
            exerciseName: addedExercise.name,
            muscleGroups: addedExercise.muscleGroups,
            order: 0,
            exerciseId: addedExercise.id
        )
        addedWorkoutExercise.workoutSession = session
        session.workoutExercises = [addedWorkoutExercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        let viewModel = WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: RecordingRestTimerReminders()
        )
        viewModel.currentSession = session

        viewModel.completeWorkout(updateTemplate: false, notes: "")

        let unchangedRoutine = try #require(routineRepository.fetch(id: routine.id))
        #expect(unchangedRoutine.routineExercisesList.map(\.id) == [slot.id])
        #expect(addedWorkoutExercise.routineExerciseId == nil)
    }

    // MARK: - Progressive overload from history (after-the-fact)

    /// Builds a completed session whose single exercise hit the top of an 8–12
    /// rep goal, wired to a still-live routine template. Returns everything a
    /// history-apply test needs. `linkRoutineExerciseId` toggles legacy history
    /// (nil slot id → resolution falls back to exercise identity).
    @MainActor
    private func makeHistoryScenario(
        context: ModelContext,
        routineRepository: SwiftDataRoutineRepository,
        sessionRepository: SwiftDataWorkoutSessionRepository,
        linkRoutineExerciseId: Bool = true
    ) throws -> (session: WorkoutSession, workoutExercise: WorkoutExercise, slot: RoutineExercise, exercise: Exercise) {
        let exercise = Exercise(name: "Bench Press", loadBehavior: .resistance)
        let routine = Routine(name: "Push")
        let slot = RoutineExercise(exercise: exercise, order: 0)
        slot.routine = routine
        slot.targetRepMin = 8
        slot.targetRepMax = 12
        routine.routineExercises = [slot]
        let templateSet = ExerciseSet(reps: 12, weight: 50, restTime: 60)
        templateSet.routineExercise = slot
        slot.sets = [templateSet]

        context.insert(exercise)
        context.insert(slot)
        context.insert(templateSet)
        routineRepository.insert(routine)

        let session = WorkoutSession(routine: routine)
        let workoutExercise = WorkoutExercise(from: slot, order: 0)
        if !linkRoutineExerciseId { workoutExercise.routineExerciseId = nil }
        workoutExercise.workoutSession = session
        for set in workoutExercise.setsList {
            set.actualReps = 12
            set.isCompleted = true
        }
        session.workoutExercises = [workoutExercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        return (session, workoutExercise, slot, exercise)
    }

    @MainActor
    private func makeViewModel(
        sessionRepository: SwiftDataWorkoutSessionRepository,
        routineRepository: SwiftDataRoutineRepository,
        exerciseRepository: SwiftDataExerciseRepository,
        healthKitManager: HealthKitWorkoutServicing? = nil
    ) -> WorkoutViewModel {
        WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository,
            healthKitManager: healthKitManager ?? MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: RecordingRestTimerReminders()
        )
    }

    // MARK: - Deleting a workout (with or without its Apple Health counterpart)

    /// A completed, persisted session carrying a HealthKit external UUID.
    @MainActor
    private func makeDeletableSession(
        sessionRepository: SwiftDataWorkoutSessionRepository,
        routineRepository: SwiftDataRoutineRepository,
        healthKitWorkoutId: UUID?
    ) throws -> WorkoutSession {
        let routine = Routine(name: "Push")
        routineRepository.insert(routine)
        let session = WorkoutSession(routine: routine)
        session.endTime = session.startTime.addingTimeInterval(3_600)
        session.healthKitWorkoutId = healthKitWorkoutId
        sessionRepository.insert(session)
        try sessionRepository.save()
        return session
    }

    @Test
    func deletingWorkoutWithAppleHealthChoiceRemovesBothCopies() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let healthKit = MockHealthKitWorkoutServicing()
        let externalUUID = UUID()
        let session = try makeDeletableSession(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository, healthKitWorkoutId: externalUUID
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: healthKit
        )

        viewModel.deleteWorkout(session, alsoFromHealthKit: true)
        await Task.yield()

        #expect(sessionRepository.fetchAll().isEmpty)
        #expect(healthKit.deletedExternalUUIDs == [externalUUID])
        #expect(viewModel.healthKitDeleteFailed == false)
    }

    @Test
    func deletingWorkoutGymStreakOnlyLeavesAppleHealthUntouched() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let healthKit = MockHealthKitWorkoutServicing()
        let session = try makeDeletableSession(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository, healthKitWorkoutId: UUID()
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: healthKit
        )

        viewModel.deleteWorkout(session, alsoFromHealthKit: false)
        await Task.yield()

        #expect(sessionRepository.fetchAll().isEmpty)
        #expect(healthKit.deletedExternalUUIDs.isEmpty)
    }

    @Test
    func deletingWorkoutWithoutHealthKitCounterpartSkipsHealthKit() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let healthKit = MockHealthKitWorkoutServicing()
        let session = try makeDeletableSession(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository, healthKitWorkoutId: nil
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: healthKit
        )

        // Even when Apple Health is requested there is nothing to remove.
        viewModel.deleteWorkout(session, alsoFromHealthKit: true)
        await Task.yield()

        #expect(sessionRepository.fetchAll().isEmpty)
        #expect(healthKit.deletedExternalUUIDs.isEmpty)
        #expect(viewModel.healthKitDeleteFailed == false)
    }

    @Test
    func healthKitDeleteFailureLeavesLocalDeleteCommitted() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let healthKit = MockHealthKitWorkoutServicing()
        healthKit.deleteError = HealthKitError.deleteFailed("denied")
        let session = try makeDeletableSession(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository, healthKitWorkoutId: UUID()
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: healthKit
        )

        viewModel.deleteWorkout(session, alsoFromHealthKit: true)
        await Task.yield()

        // The local delete stands; the failure only raises the non-blocking flag.
        #expect(sessionRepository.fetchAll().isEmpty)
        #expect(viewModel.workoutHistory.isEmpty)
        #expect(viewModel.healthKitDeleteFailed)
    }

    @Test
    func alreadyAbsentHealthKitWorkoutIsNotTreatedAsFailure() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let healthKit = MockHealthKitWorkoutServicing()
        // No match: already deleted in the Health app, or the read was denied.
        healthKit.deleteResult = false
        let session = try makeDeletableSession(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository, healthKitWorkoutId: UUID()
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            healthKitManager: healthKit
        )

        viewModel.deleteWorkout(session, alsoFromHealthKit: true)
        await Task.yield()

        #expect(sessionRepository.fetchAll().isEmpty)
        #expect(viewModel.healthKitDeleteFailed == false)
    }

    @Test
    func applyingOverloadFromHistoryBumpsLiveTemplateAndLeavesHistoryUnchanged() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository, exerciseRepository: exerciseRepository
        )

        // Snapshot the historical set before applying — it must not change.
        let historySet = try #require(scenario.workoutExercise.setsList.first)
        let before = (historySet.actualWeight, historySet.actualReps, historySet.plannedWeight, historySet.plannedReps)

        #expect(viewModel.hasResolvableOverloadTemplate(from: scenario.session, for: scenario.workoutExercise))
        let newWeight = viewModel.applyProgressiveOverloadFromHistory(
            from: scenario.session, for: scenario.workoutExercise, weightIncrement: 2.5
        )

        // Live template bumped: +2.5 kg, reps reset to the range minimum.
        #expect(newWeight == 52.5)
        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.weight == 52.5)
        #expect(templateSet.reps == 8)

        // History is immutable: nothing on the workout set or its flag changed.
        #expect(historySet.actualWeight == before.0)
        #expect(historySet.actualReps == before.1)
        #expect(historySet.plannedWeight == before.2)
        #expect(historySet.plannedReps == before.3)
        #expect(scenario.workoutExercise.progressiveOverloadApplied == false)
    }

    @Test
    func applyingOverloadFromHistoryResolvesRenamedExerciseViaIdentityFallback() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
        // Legacy history (no slot id) forces resolution through exercise identity.
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository,
            linkRoutineExerciseId: false
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository, exerciseRepository: exerciseRepository
        )

        // Rename the live library exercise after the workout — identity (id) still matches.
        scenario.exercise.name = "Barbell Bench Press"

        #expect(viewModel.hasResolvableOverloadTemplate(from: scenario.session, for: scenario.workoutExercise))
        let newWeight = viewModel.applyProgressiveOverloadFromHistory(
            from: scenario.session, for: scenario.workoutExercise, weightIncrement: 5
        )
        #expect(newWeight == 55)
        #expect(try #require(scenario.slot.setsList.first).weight == 55)
    }

    @Test
    func applyingOverloadFromHistoryIsNoOpWhenRoutineDeleted() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let exerciseRepository = SwiftDataExerciseRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository, exerciseRepository: exerciseRepository
        )

        // Simulate the source routine being deleted since the workout.
        scenario.session.routine = nil

        #expect(viewModel.hasResolvableOverloadTemplate(from: scenario.session, for: scenario.workoutExercise) == false)
        let newWeight = viewModel.applyProgressiveOverloadFromHistory(
            from: scenario.session, for: scenario.workoutExercise, weightIncrement: 2.5
        )
        #expect(newWeight == nil)
        // The now-orphaned template slot is untouched.
        #expect(try #require(scenario.slot.setsList.first).weight == 50)
    }
}
