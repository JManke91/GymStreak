//
//  HistoryGateLatencyHarness.swift
//  GymStreakTests
//
//  The fixture and the stopwatch behind `HistoryGateLatencyTests` — the store that
//  crashed, rebuilt on disk, and a way to time a writer's wait on `HistoryStoreGate`
//  that does not depend on scheduling luck.
//
//  Kept out of the test file so the measurements read as measurements. The shared
//  `WorkoutViewModel` fixture and the `AsyncSignal` latch live here too; both are
//  duplicated privately in `HistoryStoreGateTests` and `HistoryDeleteRaceRegressionTests`,
//  and this is where those copies should collapse to.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

enum HistoryGateLatencyHarness {

    // MARK: - Fixture shape (the store that crashed)

    /// 49 × 7 = 343 `WorkoutExercise` rows, against the 341 the device held when it trapped.
    static let sessionCount = 49
    static let exercisesPerSession = 7
    static let setsPerExercise = 3
    static let catalogSize = 96
    static let routineCount = 4

    struct Fixture {
        let trainedExerciseIDs: [UUID]
        let trainedExerciseNames: [String]
    }

    /// The crash store, rebuilt: a full starter catalog, four scheduled routines, and 49
    /// completed sessions of seven exercises each.
    ///
    /// The catalog and the routines are not padding. `SwiftDataHistorySnapshotStore` fetches
    /// the **entire** `Exercise` table and every `Routine` with `\.schedules` prefetched on
    /// each read, and `fetchLiveRoutineSlotIds` walks `routineExercisesList` — so leaving
    /// them out would measure a gate holding a fraction of the real work.
    @MainActor
    static func seed(into context: ModelContext) throws -> Fixture {
        var library: [Exercise] = []
        for index in 0..<catalogSize {
            let exercise = Exercise(
                name: "Exercise \(index)",
                muscleGroups: ["Chest", "Triceps"],
                equipmentType: .barbell
            )
            context.insert(exercise)
            library.append(exercise)
        }
        let trained = Array(library.prefix(exercisesPerSession))

        // Slot ids per routine, so the workout rows carry a real `routineExerciseId` and the
        // usage attribution has something to resolve against.
        var slotIDsByRoutine: [[UUID]] = []
        for routineIndex in 0..<routineCount {
            let routine = Routine(name: "Routine \(routineIndex)")
            context.insert(routine)

            let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 2)
            context.insert(schedule)
            schedule.routine = routine
            routine.schedules = [schedule]

            var slotIDs: [UUID] = []
            for (order, exercise) in trained.enumerated() {
                let slot = RoutineExercise(exercise: exercise, order: order)
                context.insert(slot)
                slot.routine = routine
                routine.routineExercises?.append(slot)
                slotIDs.append(slot.id)
            }
            slotIDsByRoutine.append(slotIDs)
        }

        let referenceDate = Date()
        for sessionIndex in 0..<sessionCount {
            let routineIndex = sessionIndex % routineCount
            let startTime = referenceDate.addingTimeInterval(-Double(sessionIndex) * 86_400)
            let session = WorkoutSession(routine: nil)
            session.routineName = "Routine \(routineIndex)"
            session.startTime = startTime
            // `endTime != nil` is the predicate both History fetches select on — without it
            // these rows are invisible to every reader and the fixture measures nothing.
            session.endTime = startTime.addingTimeInterval(3_600)
            context.insert(session)

            for order in 0..<exercisesPerSession {
                let libraryExercise = trained[order]
                let workoutExercise = WorkoutExercise(
                    exerciseName: libraryExercise.name,
                    muscleGroups: libraryExercise.muscleGroups,
                    order: order,
                    exerciseId: libraryExercise.id,
                    routineExerciseId: slotIDsByRoutine[routineIndex][order]
                )
                workoutExercise.workoutSession = session
                context.insert(workoutExercise)

                for setOrder in 0..<setsPerExercise {
                    let weight = Double(60 + order) + Double(sessionIndex % 5)
                    let set = WorkoutSet(
                        plannedReps: 8,
                        actualReps: 8,
                        plannedWeight: weight,
                        actualWeight: weight,
                        restTime: 90,
                        order: setOrder
                    )
                    set.isCompleted = true
                    set.workoutExercise = workoutExercise
                    context.insert(set)
                    workoutExercise.sets?.append(set)
                }

                session.workoutExercises?.append(workoutExercise)
            }
        }

        try context.save()
        return Fixture(
            trainedExerciseIDs: trained.map(\.id),
            trainedExerciseNames: trained.map(\.name)
        )
    }

    /// Pins the shape every quoted number rests on. The doc and `HistoryStoreGate`'s own
    /// comment cite "343 exercise rows"; if the seed drifts, the citations become wrong
    /// silently.
    @MainActor
    static func verifyFixtureShape(_ context: ModelContext) throws {
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == sessionCount)
        #expect(
            try context.fetchCount(FetchDescriptor<WorkoutExercise>())
                == sessionCount * exercisesPerSession
        )
        #expect(
            try context.fetchCount(FetchDescriptor<WorkoutSet>())
                == sessionCount * exercisesPerSession * setsPerExercise
        )
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == catalogSize)
    }

    // MARK: - The stopwatch

    struct WriteBehindResult {
        /// How long the write took from the moment the gate was handed to the queue.
        let wait: Duration
        /// Completion order, as labels: the readers by index, then `"write"`. The FIFO
        /// order under test is only *intended* by the spawn sequence, so it is asserted
        /// rather than assumed.
        let completionOrder: [String]

        var writeWentLast: Bool { completionOrder.last == "write" }
    }

    /// Queues `fanOut` and then `write` behind a stand-in holder, releases it, and returns
    /// how long `write` took from that release.
    ///
    /// The holder is what makes the number reproducible: without it the write races the
    /// readers to `acquire()` and the measurement is really a measurement of scheduling
    /// luck. With it the FIFO order is known, so the result is the write's worst case for
    /// this fan-out — the wait a user gets when they tap the instant the reads begin.
    ///
    /// The fan-out is run **once, uncontended, before the holder takes the gate**. Every
    /// provider builds its `@ModelActor` behind a `Task.detached` and awaits it *before*
    /// `gate.withAccess`, so an unwarmed reader can still be constructing while the write
    /// enqueues ahead of it — which would quietly drop that reader out of the measured wait
    /// and under-report the ceiling.
    ///
    /// - Parameter cancelFanOutOnceQueued: cancels every queued reader before the holder
    ///   releases, which is what `.task(id:)` does to a superseded rebuild. `acquire` is not
    ///   cancellation-aware, so the readers keep their place in the queue either way.
    @MainActor
    static func measureWriteBehind(
        fanOut: [@Sendable () async -> Void],
        cancelFanOutOnceQueued: Bool = false,
        gate: HistoryStoreGate,
        write: @escaping @MainActor () async -> Void
    ) async -> WriteBehindResult {
        for work in fanOut { await work() }

        let clock = ContinuousClock()
        let order = CompletionOrder()
        let holderEntered = AsyncSignal()
        let releaseHolder = AsyncSignal()

        let holder = Task {
            await gate.withAccess {
                holderEntered.fire()
                await releaseHolder.wait()
            }
        }
        await holderEntered.wait()

        var readers: [Task<Void, Never>] = []
        for (index, work) in fanOut.enumerated() {
            readers.append(Task {
                await work()
                order.record("reader \(index)")
            })
            // Long enough for the reader to reach `acquire()` and take its place in the
            // queue. Without the pause the queue order is whatever the executor decides.
            try? await Task.sleep(for: .milliseconds(10))
        }

        let finished = Task { @MainActor () -> ContinuousClock.Instant in
            await write()
            order.record("write")
            return clock.now
        }
        try? await Task.sleep(for: .milliseconds(10))

        if cancelFanOutOnceQueued {
            for reader in readers { reader.cancel() }
        }

        let released = clock.now
        releaseHolder.fire()

        let end = await finished.value
        await holder.value
        for reader in readers { await reader.value }
        return WriteBehindResult(
            wait: released.duration(to: end),
            completionOrder: order.labels
        )
    }

    @discardableResult
    static func measure<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await body()
        report(label, start.duration(to: clock.now))
        return value
    }

    /// Printed rather than asserted: the numbers are the deliverable, the `#expect`s are
    /// only tripwires. Grep a test log for `GATE-COST`.
    static func report(_ label: String, _ duration: Duration) {
        let milliseconds = Double(duration.components.attoseconds) / 1e15
            + Double(duration.components.seconds) * 1000
        print(String(format: "GATE-COST %@: %.1f ms", label, milliseconds))
    }

    // MARK: - View model under test

    @MainActor
    static func makeViewModel(context: ModelContext, gate: HistoryStoreGate) -> WorkoutViewModel {
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
}

// MARK: - Doubles

final class EmptyHistoryCorrelation: WorkoutHistoryCorrelationProviding {
    func healthKitWorkoutIDs() throws -> Set<UUID> { [] }
    func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID? { nil }
}

final class NoopRestTimerReminders: RestTimerReminderScheduling {
    func scheduleReminder(id: UUID, deadline: Date) async -> RestTimerReminderOutcome { .scheduled }
    func cancelReminder(id: UUID) {}
}

/// Records what finished, in what order, from tasks on several executors.
///
/// `@unchecked Sendable` invariant: `entries` is only ever touched under `lock`.
final class CompletionOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ label: String) {
        lock.lock()
        entries.append(label)
        lock.unlock()
    }

    var labels: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

/// One-shot latch, so sequencing never depends on a sleep.
///
/// `@unchecked Sendable` invariant: `isFired` and `waiters` are only ever touched under
/// `lock`, and continuations are resumed after unlocking, so no continuation is resumed
/// while the lock is held and no state is touched outside it.
final class AsyncSignal: @unchecked Sendable {
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
