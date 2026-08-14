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

    /// History uses an invalidation version rather than retaining every SwiftData model on
    /// MainActor. Content-only edits and CloudKit modifies do not change a count, so every explicit
    /// refresh must still advance the generation.
    @MainActor
    @Test
    func historyVersionChangesOnEveryRefreshAndSingleSessionLookupStillWorks() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository,
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )

        let session = WorkoutSession(routine: nil)
        session.endTime = session.startTime.addingTimeInterval(600)
        sessionRepository.insert(session)
        try sessionRepository.save()

        viewModel.refreshHistory()
        let afterFirstRefresh = viewModel.historyVersion

        // Mutating in place: the session count cannot signal this change.
        session.notes = "edited"
        try sessionRepository.save()
        viewModel.refreshHistory()

        #expect(viewModel.historyVersion != afterFirstRefresh)
        #expect(viewModel.workoutSession(id: session.id) === session)
    }

    @Test
    func restTimerRemindersAreDeferredUntilTimerStarts() async {
        let context = ModelContext(InMemoryModelContainer.make())
        let reminders = RecordingRestTimerReminders()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = makeViewModel(
            sessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
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
        let viewModel = makeViewModel(
            sessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
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
        let viewModel = makeViewModel(
            sessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            now: { currentDate }
        )

        viewModel.startRestTimer(duration: 60)
        currentDate = currentDate.addingTimeInterval(25)
        viewModel.restoreTimerState()

        #expect(viewModel.restTimeRemaining == 35)
        viewModel.stopRestTimer()
    }

    // MARK: - Rest timer Live Activity

    /// The Lock Screen countdown is a third delivery surface for the *same*
    /// timer identity the notification and the persisted state use. Creating a
    /// ViewModel must only clear a previous process's leftovers — never present
    /// anything — and starting a timer must hand the presenter the routine, the
    /// exercise the user is resting from, and the authoritative deadline.
    @Test
    func startingARestTimerPresentsTheCountdownUnderTheTimerIdentity() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let reminders = RecordingRestTimerReminders()
        let liveActivity = RecordingRestTimerLiveActivity()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            restTimerReminders: reminders,
            restTimerLiveActivity: liveActivity,
            now: { now }
        )

        #expect(liveActivity.dismissExpiredCallCount == 1)
        #expect(liveActivity.startedActivities.isEmpty)

        let routine = Routine(name: "Push")
        routineRepository.insert(routine)
        let session = WorkoutSession(routine: routine)
        let workoutExercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["Chest"],
            order: 0
        )
        workoutExercise.workoutSession = session
        session.workoutExercises = [workoutExercise]
        sessionRepository.insert(session)
        viewModel.currentSession = session

        viewModel.startRestTimer(duration: 60)
        await Task.yield()

        #expect(liveActivity.startedActivities.count == 1)
        let started = try #require(liveActivity.startedActivities.first)
        #expect(started.content.workoutName == "Push")
        #expect(started.content.exerciseName == "Bench Press")
        #expect(started.content.startDate == now)
        #expect(started.content.deadline == now.addingTimeInterval(60))
        // One identity across every surface of this timer.
        #expect(started.id == reminders.scheduledReminders.first?.id)

        viewModel.stopRestTimer()

        #expect(liveActivity.endedActivityIDs == [started.id])
    }

    /// Restoring after a background/relaunch re-presents the *same* timer id
    /// rather than a new one, so the presenter can recognise the countdown it is
    /// already showing instead of requesting a duplicate Live Activity.
    @Test
    func restoringARestTimerRepresentsTheSameLiveActivityIdentity() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let liveActivity = RecordingRestTimerLiveActivity()
        var currentDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let viewModel = makeViewModel(
            sessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            restTimerLiveActivity: liveActivity,
            now: { currentDate }
        )

        viewModel.startRestTimer(duration: 60)
        currentDate = currentDate.addingTimeInterval(25)
        viewModel.restoreTimerState()

        #expect(liveActivity.startedActivities.count == 2)
        let first = try #require(liveActivity.startedActivities.first)
        let second = try #require(liveActivity.startedActivities.last)
        #expect(first.id == second.id)
        // The absolute deadline survives the round trip through UserDefaults.
        #expect(second.content.deadline == first.content.deadline)

        viewModel.stopRestTimer()
        #expect(liveActivity.endedActivityIDs == [first.id])
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

        let viewModel = makeViewModel(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository
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

        let viewModel = makeViewModel(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository
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

        let viewModel = makeViewModel(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository
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

        let viewModel = makeViewModel(
            sessionRepository: sessionRepository,
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository
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
    /// The single `WorkoutViewModel` construction point for this suite. Both
    /// system surfaces of the rest timer (the local notification and the Live
    /// Activity) default to recording doubles, so no test touches
    /// `UNUserNotificationCenter` or ActivityKit in the test host.
    private func makeViewModel(
        sessionRepository: SwiftDataWorkoutSessionRepository,
        routineRepository: SwiftDataRoutineRepository,
        exerciseRepository: SwiftDataExerciseRepository,
        healthKitManager: HealthKitWorkoutServicing? = nil,
        restTimerReminders: RestTimerReminderScheduling? = nil,
        restTimerLiveActivity: RestTimerLiveActivityPresenting? = nil,
        now: (() -> Date)? = nil
    ) -> WorkoutViewModel {
        WorkoutViewModel(
            workoutSessionRepository: sessionRepository,
            routineRepository: routineRepository,
            healthKitManager: healthKitManager ?? MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyWorkoutHistoryCorrelationProvider(),
            restTimerReminders: restTimerReminders ?? RecordingRestTimerReminders(),
            restTimerLiveActivity: restTimerLiveActivity ?? RecordingRestTimerLiveActivity(),
            routineTemplateSync: RoutineTemplateSyncService(
                routineRepository: routineRepository,
                exerciseRepository: exerciseRepository
            ),
            now: now ?? Date.init
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

    /// The mid-workout increase belongs to the NEXT workout. It is only offered
    /// once every set of the exercise is completed at the rep max, so writing
    /// the proposal into the live sets would rewrite work already done and show
    /// the user numbers they never lifted.
    @Test
    func applyingOverloadMidWorkoutRaisesTheTemplateWithoutRewritingThePerformance() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )
        viewModel.currentSession = scenario.session
        let performedSet = try #require(scenario.workoutExercise.setsList.first)

        viewModel.applyProgressiveOverload(for: scenario.workoutExercise, weightIncrement: 2.5)

        // The template — and only the template — moves.
        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.weight == 52.5)
        #expect(templateSet.reps == 8)
        #expect(viewModel.appliedOverloadWeight(for: scenario.workoutExercise) == 52.5)
        #expect(viewModel.hasNonUniformAppliedOverload(for: scenario.workoutExercise) == false)

        // What the user actually lifted stays on the workout, in BOTH fields:
        // `progressiveOverloadApplied` makes every aggregator read the planned
        // ones back out, so they have to carry the performance too.
        #expect(performedSet.actualWeight == 50)
        #expect(performedSet.actualReps == 12)
        #expect(performedSet.plannedWeight == 50)
        #expect(performedSet.plannedReps == 12)
        #expect(scenario.workoutExercise.progressiveOverloadApplied)
    }

    /// The default-on "Update routine template" toggle writes every completed
    /// set's performed values back into the template. Those values are, for an
    /// overloaded exercise, the weights from BEFORE the increase — writing them
    /// back would silently undo it (and re-qualify the exercise at once).
    @Test
    func savingWithTemplateUpdateDoesNotWriteThePerformanceOverAnAppliedIncrease() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )
        viewModel.currentSession = scenario.session
        viewModel.applyProgressiveOverload(for: scenario.workoutExercise, weightIncrement: 2.5)

        viewModel.completeWorkout(updateTemplate: true, notes: "")

        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.weight == 52.5)
        #expect(templateSet.reps == 8)
    }

    /// The same writeback must still work for an ordinary exercise — the
    /// exclusion above is scoped to overload-applied ones only.
    @Test
    func savingWithTemplateUpdateStillWritesThePerformanceForAnOrdinaryExercise() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )
        viewModel.currentSession = scenario.session
        let performedSet = try #require(scenario.workoutExercise.setsList.first)
        performedSet.actualWeight = 55

        viewModel.completeWorkout(updateTemplate: true, notes: "")

        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.weight == 55)
        #expect(templateSet.reps == 12)
    }

    /// A set added during the workout has no template counterpart the increase
    /// could have raised, so it must join the RAISED scheme — otherwise Save
    /// leaves the template mixing raised and unraised sets.
    @Test
    func aSetAddedDuringAnOverloadedWorkoutJoinsTheRaisedTemplateScheme() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )
        viewModel.currentSession = scenario.session
        viewModel.applyProgressiveOverload(for: scenario.workoutExercise, weightIncrement: 2.5)

        // A second, extra set performed at the old weight.
        let extra = WorkoutSet(
            plannedReps: 12, actualReps: 12, plannedWeight: 50, actualWeight: 50,
            restTime: 60, order: 1
        )
        extra.isCompleted = true
        extra.workoutExercise = scenario.workoutExercise
        scenario.workoutExercise.sets?.append(extra)
        context.insert(extra)

        viewModel.completeWorkout(updateTemplate: true, notes: "")

        let templateSets = scenario.slot.setsList.sorted { $0.order < $1.order }
        #expect(templateSets.count == 2)
        #expect(templateSets.allSatisfy { $0.weight == 52.5 })
        #expect(templateSets.allSatisfy { $0.reps == 8 })
    }

    /// A nonuniform (pyramid) target has no single weight that is true of the
    /// exercise, so the card must be told to say "all sets adjusted" instead.
    @Test
    func anOverloadOnANonuniformSchemeReportsNoSingleAppliedWeight() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        // Second template set at a different weight — a pyramid scheme.
        let heavier = ExerciseSet(reps: 12, weight: 60, restTime: 60, order: 1)
        heavier.routineExercise = scenario.slot
        scenario.slot.sets?.append(heavier)
        context.insert(heavier)
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )
        viewModel.currentSession = scenario.session

        viewModel.applyProgressiveOverload(for: scenario.workoutExercise, weightIncrement: 2.5)

        #expect(viewModel.hasNonUniformAppliedOverload(for: scenario.workoutExercise))
        #expect(viewModel.appliedOverloadWeight(for: scenario.workoutExercise) == nil)
        #expect(scenario.slot.setsList.sorted { $0.order < $1.order }.map(\.weight) == [52.5, 62.5])
    }

    @Test
    func undoingAMidWorkoutOverloadRestoresTheTemplateAndClearsTheAppliedWeight() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let scenario = try makeHistoryScenario(
            context: context, routineRepository: routineRepository, sessionRepository: sessionRepository
        )
        let viewModel = makeViewModel(
            sessionRepository: sessionRepository, routineRepository: routineRepository,
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
        )
        viewModel.currentSession = scenario.session
        viewModel.applyProgressiveOverload(for: scenario.workoutExercise, weightIncrement: 2.5)

        viewModel.undoProgressiveOverload(for: scenario.workoutExercise)

        let templateSet = try #require(scenario.slot.setsList.first)
        #expect(templateSet.weight == 50)
        #expect(templateSet.reps == 12)
        #expect(scenario.workoutExercise.progressiveOverloadApplied == false)
        #expect(viewModel.appliedOverloadWeight(for: scenario.workoutExercise) == nil)
        #expect(viewModel.hasNonUniformAppliedOverload(for: scenario.workoutExercise) == false)
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
