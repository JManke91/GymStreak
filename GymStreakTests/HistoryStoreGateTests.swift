//
//  HistoryStoreGateTests.swift
//  GymStreakTests
//
//  Regression cover for the History delete race (docs/history-delete-race.md).
//
//  The crash it prevents cannot be asserted directly: SwiftData's reaction to reading a
//  row another context deleted is an uncatchable `fatalError`, so a test that reproduced
//  it would kill the test runner rather than fail. These tests assert the two properties
//  that make the crash impossible instead — the gate really is exclusive, and
//  `WorkoutViewModel`'s completed-session delete really takes it.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
struct HistoryStoreGateTests {

    /// Counts how many holders are inside the gate at once.
    private actor ConcurrencyTracker {
        private var current = 0
        private(set) var maxConcurrent = 0
        private(set) var completed = 0

        func enter() {
            current += 1
            maxConcurrent = max(maxConcurrent, current)
        }

        func exit() {
            current -= 1
            completed += 1
        }
    }

    @Test
    func onlyOneHolderIsInsideTheGateAtATime() async {
        let gate = HistoryStoreGate()
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await gate.withAccess {
                        await tracker.enter()
                        // Long enough that a broken gate would overlap holders rather than
                        // happening to serialize them by scheduling luck.
                        try? await Task.sleep(for: .milliseconds(5))
                        await tracker.exit()
                    }
                }
            }
        }

        #expect(await tracker.maxConcurrent == 1)
        // Also proves nothing was dropped or deadlocked in the waiter queue.
        #expect(await tracker.completed == 12)
    }

    /// A throwing body must still release, or the first failed snapshot build would wedge
    /// every later read and every delete behind it. Asserted for *both* entry points —
    /// `withAccess` (readers) and `withExclusiveAccess` (writers) — since each brackets
    /// `acquire`/`release` itself.
    @Test
    func aThrowingBodyStillReleasesTheGate() async throws {
        struct Boom: Error {}
        let gate = HistoryStoreGate()

        await #expect(throws: Boom.self) {
            try await gate.withAccess { throw Boom() }
        }

        // Would hang here if the gate were still held.
        let reacquired = await gate.withAccess { true }
        #expect(reacquired)

        await #expect(throws: Boom.self) {
            try await gate.withExclusiveAccess { throw Boom() }
        }

        let reacquiredAfterWriter = await gate.withExclusiveAccess { true }
        #expect(reacquiredAfterWriter)
    }

    /// The two entry points are one gate, not two. A writer entering through
    /// `withExclusiveAccess` must wait behind a reader holding via `withAccess` — if they ever
    /// came apart, every writer call site would silently stop excluding the History actor.
    @Test
    @MainActor
    func aWriterWaitsBehindAReaderHoldingTheSameGate() async {
        let gate = HistoryStoreGate()
        let releaseReader = AsyncSignal()
        let readerHasEntered = AsyncSignal()
        let writerDidRun = RunFlag()

        let reader = Task {
            await gate.withAccess {
                readerHasEntered.fire()
                await releaseReader.wait()
            }
        }
        await readerHasEntered.wait()

        let writer = Task { @MainActor in
            await gate.withExclusiveAccess { writerDidRun.didRun = true }
        }

        // Still blocked: the reader holds. The sleep also yields the main actor, so a writer
        // that did *not* wait would have run by now.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(writerDidRun.didRun == false, "a writer ran while a reader held the gate")

        releaseReader.fire()
        await reader.value
        await writer.value

        #expect(writerDidRun.didRun)
    }

    /// The wiring test: deleting a completed workout must wait for whoever holds the gate.
    /// This is what stops a delete from landing inside the History model actor's walk of
    /// the completed-session graph.
    @Test
    @MainActor
    func deletingACompletedWorkoutWaitsForTheGate() async throws {
        let gate = HistoryStoreGate()
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let viewModel = makeViewModel(context: context, gate: gate)

        let session = WorkoutSession(routine: nil)
        session.endTime = session.startTime.addingTimeInterval(600)
        sessionRepository.insert(session)
        try sessionRepository.save()
        let sessionID = session.id

        // Stand in for an in-flight snapshot build holding the gate.
        let releaseReader = AsyncSignal()
        let readerHasEntered = AsyncSignal()
        let reader = Task {
            await gate.withAccess {
                readerHasEntered.fire()
                await releaseReader.wait()
            }
        }
        await readerHasEntered.wait()

        let delete = Task { @MainActor in
            await viewModel.deleteWorkout(session)
        }

        // The delete must still be blocked: the row is untouched while the reader holds.
        try await Task.sleep(for: .milliseconds(50))
        #expect(
            sessionRepository.findSession(id: sessionID, healthKitWorkoutId: nil) != nil,
            "delete ran while the History gate was held — the race is back"
        )

        releaseReader.fire()
        await reader.value
        await delete.value

        #expect(sessionRepository.findSession(id: sessionID, healthKitWorkoutId: nil) == nil)
    }

    /// The regression that the first version of this fix got wrong.
    ///
    /// `pauseForCompletion()` persists `endTime` while the workout is still `currentSession`,
    /// so an "in-workout" deletion can remove rows the History actor is walking. If
    /// `withHistoryGateIfVisible` ever reverts to excluding in-workout writers outright, this
    /// fails — the plain `deleteWorkout` test would not.
    @Test
    @MainActor
    func anInWorkoutDeleteWaitsForTheGateOnceTheSessionHasAnEndTime() async throws {
        let gate = HistoryStoreGate()
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let viewModel = makeViewModel(context: context, gate: gate)

        let session = WorkoutSession(routine: nil)
        let exercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["Chest"],
            order: 0
        )
        exercise.workoutSession = session
        session.workoutExercises = [exercise]
        sessionRepository.insert(session)
        try sessionRepository.save()

        viewModel.currentSession = session
        // Exactly what `pauseForCompletion()` leaves behind: finished, saved, still editable.
        session.endTime = Date()
        try sessionRepository.save()
        let exerciseID = exercise.id

        let releaseReader = AsyncSignal()
        let readerHasEntered = AsyncSignal()
        let reader = Task {
            await gate.withAccess {
                readerHasEntered.fire()
                await releaseReader.wait()
            }
        }
        await readerHasEntered.wait()

        let remove = Task { @MainActor in
            await viewModel.removeExerciseFromWorkout(exercise)
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(
            session.workoutExercisesList.contains { $0.id == exerciseID },
            "in-workout delete ran while the gate was held, though endTime made the row visible"
        )

        releaseReader.fire()
        await reader.value
        await remove.value

        #expect(session.workoutExercisesList.isEmpty == true)
    }

    /// During a normal workout (`endTime == nil`) the row is outside the History fetches, so
    /// the edit must not wait on a rebuild — that is the whole point of gating conditionally.
    @Test
    @MainActor
    func anInWorkoutDeleteDoesNotWaitWhileTheSessionIsStillRunning() async throws {
        let gate = HistoryStoreGate()
        let context = ModelContext(InMemoryModelContainer.make())
        let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let viewModel = makeViewModel(context: context, gate: gate)

        let session = WorkoutSession(routine: nil)
        let exercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["Chest"],
            order: 0
        )
        exercise.workoutSession = session
        session.workoutExercises = [exercise]
        sessionRepository.insert(session)
        try sessionRepository.save()
        viewModel.currentSession = session
        #expect(session.endTime == nil)

        let releaseReader = AsyncSignal()
        let readerHasEntered = AsyncSignal()
        let reader = Task {
            await gate.withAccess {
                readerHasEntered.fire()
                await releaseReader.wait()
            }
        }
        await readerHasEntered.wait()

        // Completes even though the gate is held by someone else.
        await viewModel.removeExerciseFromWorkout(exercise)
        #expect(session.workoutExercisesList.isEmpty == true)

        releaseReader.fire()
        await reader.value
    }

    // MARK: - Doubles

    /// Records whether a synchronous gated body ran. `@MainActor` rather than an actor because
    /// the writer entry point's closure is synchronous and so cannot `await`.
    @MainActor
    private final class RunFlag {
        var didRun = false
    }

    @MainActor
    private func makeViewModel(context: ModelContext, gate: HistoryStoreGate) -> WorkoutViewModel {
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        return WorkoutViewModel(
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: routineRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyHistoryCorrelation(),
            restTimerReminders: NoopRestTimerReminders(),
            restTimerLiveActivity: RecordingRestTimerLiveActivity(),
            routineTemplateSync: RoutineTemplateSyncService(
                routineRepository: routineRepository,
                exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
            ),
            historyStoreGate: gate
        )
    }

    private final class EmptyHistoryCorrelation: WorkoutHistoryCorrelationProviding {
        func healthKitWorkoutIDs() throws -> Set<UUID> { [] }
        func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID? { nil }
    }

    private final class NoopRestTimerReminders: RestTimerReminderScheduling {
        func scheduleReminder(id: UUID, deadline: Date) async -> RestTimerReminderOutcome { .scheduled }
        func cancelReminder(id: UUID) {}
    }

    /// One-shot latch so the test never depends on a sleep to sequence the two tasks.
    ///
    /// `@unchecked Sendable` invariant: every access to `isFired` and `waiters` happens under
    /// `lock`, and continuations are resumed after unlocking, so no continuation is resumed
    /// while the lock is held and no state is touched outside it.
    private final class AsyncSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var isFired = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func fire() {
            lock.lock()
            guard !isFired else { lock.unlock(); return }
            isFired = true
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            pending.forEach { $0.resume() }
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if isFired {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }
    }
}
