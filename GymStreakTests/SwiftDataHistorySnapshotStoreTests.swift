//
//  SwiftDataHistorySnapshotStoreTests.swift
//  GymStreakTests
//
//  Integration coverage for History's actor-owned read boundary — and, since audit
//  §6, the shared main-actor tripwire suite for **every** `@concurrent` read boundary
//  in the app, whichever model actor backs it. The `MainActorHeartbeat` harness at the
//  bottom is the reusable part. A new boundary adds a case here rather than a one-off
//  test file (docs/swift6-concurrency.md §10 rule 6): one growing suite is far likelier
//  to actually be run.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct SwiftDataHistorySnapshotStoreTests {
    @Test
    func largeSnapshotBuildKeepsMainActorResponsive() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 240, context: context)

        // Typed as the existential on purpose: production dispatches through
        // `any HistorySnapshotProviding` (`HistoryViewModel.provider`), and the
        // `@concurrent` guarantee has to survive the witness, not just a direct
        // concrete call. Testing the concrete type would leave the real path unguarded.
        let provider: any HistorySnapshotProviding =
            SwiftDataHistorySnapshotProvider(modelContainer: container)
        let heartbeat = MainActorHeartbeat(interval: .milliseconds(10))
        let heartbeatTask = Task { await heartbeat.run() }
        await Task.yield()

        let snapshot = try await provider.fetchTrainingSnapshot(referenceDate: Date())

        heartbeatTask.cancel()
        await heartbeatTask.value

        #expect(snapshot.sessionCount == 240)
        #expect(
            heartbeat.sampleCount >= 1,
            "the main actor should run while the model actor is building the snapshot"
        )
        #expect(
            heartbeat.maximumDelay < .milliseconds(100),
            "History snapshot work delayed MainActor by \(heartbeat.maximumDelay)"
        )
    }

    /// The exercise detail screen's read boundary joins the same tripwire suite.
    ///
    /// Audit P1.2: this path used to be a **fully synchronous** `fetchProgressData` call
    /// from a `@MainActor` view model — an unbounded fetch plus a full relationship
    /// traversal with no `await` anywhere in the chain, on every chart open and every
    /// range-pill tap. There was no async boundary at all to lose, which is why a build
    /// could never have caught it. Adding the case here rather than in a one-off test is
    /// the audit §6 recommendation: one growing suite is far likelier to be run.
    @Test
    func largeExerciseProgressBuildKeepsMainActorResponsive() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 240, context: context)

        // Existential on purpose — see the note in the training-snapshot test above.
        let provider: any HistorySnapshotProviding =
            SwiftDataHistorySnapshotProvider(modelContainer: container)
        let heartbeat = MainActorHeartbeat(interval: .milliseconds(10))
        let heartbeatTask = Task { await heartbeat.run() }
        await Task.yield()

        let snapshot = try await provider.fetchExerciseProgress(
            exerciseName: "Exercise 0",
            exerciseId: nil,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        heartbeatTask.cancel()
        await heartbeatTask.value

        #expect(snapshot.data.dataPoints.count == 240)
        #expect(snapshot.recentSessions.count == 8)
        #expect(
            heartbeat.sampleCount >= 1,
            "the main actor should run while the model actor is building the chart"
        )
        #expect(
            heartbeat.maximumDelay < .milliseconds(100),
            "Exercise progress work delayed MainActor by \(heartbeat.maximumDelay)"
        )
    }

    /// The AI-coach chat's fact boundary joins the same tripwire suite.
    ///
    /// Audit P1.3: `ChatFactProviding` used to be `@MainActor` with **synchronous**
    /// methods, and its doc comment stated the intent — a tool running off the main
    /// actor would `await` to hop *onto* it and there do an unbounded, unprefetched
    /// fetch plus a session × exercise × set scan. That fired live, mid-conversation,
    /// possibly several times per turn, while the answer was streaming.
    ///
    /// A different model actor (`ChatFactStore`) backs this one, which is exactly why
    /// the case belongs here: the harness asserts the *property* — no boundary stalls
    /// the main actor — not one store's implementation.
    @Test
    func chatFactLookupKeepsMainActorResponsive() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 240, context: context)
        // The library entry matters: without it the name resolver short-circuits to
        // `__NO_MATCH__` and never scans a single session, which would make this a
        // tripwire that can't trip.
        context.insert(Exercise(name: "Exercise 0"))
        try context.save()

        // Existential on purpose — see the note in the training-snapshot test above.
        // The chat tools likewise hold `any ChatFactProviding`.
        let provider: any ChatFactProviding = ChatFactProvider(modelContainer: container)
        let heartbeat = MainActorHeartbeat(interval: .milliseconds(10))
        let heartbeatTask = Task { await heartbeat.run() }
        await Task.yield()

        let line = await provider.exercisePRFacts(exerciseName: "Exercise 0")

        heartbeatTask.cancel()
        await heartbeatTask.value

        #expect(line.contains("personal record"))
        #expect(
            heartbeat.sampleCount >= 1,
            "the main actor should run while the fact actor is scanning history"
        )
        #expect(
            heartbeat.maximumDelay < .milliseconds(100),
            "Chat fact lookup delayed MainActor by \(heartbeat.maximumDelay)"
        )
    }

    /// Cancellation must survive the `@concurrent` hop.
    ///
    /// `SwiftDataHistorySnapshotProvider`'s methods are `@concurrent` (SE-0461) so
    /// they always leave the caller's actor — see the comment on that type. The
    /// actor behind them relies on `Task.checkCancellation()` in ten places, and
    /// `HistoryViewModel` cancels in-flight snapshot loads, so that reliance is
    /// load-bearing. `@concurrent` keeps the callee inside the caller's task tree
    /// (unlike `Task.detached`, which would sever it) — this test is what proves
    /// it, because nothing else in the suite covers cancellation of a fetch.
    @Test
    func cancellingTheCallerPropagatesThroughTheConcurrentHop() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 20, context: context)

        // Typed as the existential on purpose: production dispatches through
        // `any HistorySnapshotProviding` (`HistoryViewModel.provider`), and the
        // `@concurrent` guarantee has to survive the witness, not just a direct
        // concrete call. Testing the concrete type would leave the real path unguarded.
        let provider: any HistorySnapshotProviding =
            SwiftDataHistorySnapshotProvider(modelContainer: container)
        let fetch = Task {
            try await provider.fetchTrainingSnapshot(referenceDate: Date())
        }
        fetch.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await fetch.value
        }
    }

    private func seedHistory(sessionCount: Int, context: ModelContext) throws {
        let referenceDate = Date()

        for sessionIndex in 0..<sessionCount {
            let startTime = referenceDate.addingTimeInterval(-Double(sessionIndex) * 86_400)
            let session = WorkoutSession(routine: nil)
            session.routineName = "Stress \(sessionIndex % 3)"
            session.startTime = startTime
            session.endTime = startTime.addingTimeInterval(3_600)
            context.insert(session)

            for exerciseIndex in 0..<5 {
                let workoutExercise = WorkoutExercise(
                    exerciseName: "Exercise \(exerciseIndex)",
                    muscleGroups: ["General"],
                    order: exerciseIndex,
                    exerciseId: nil
                )
                workoutExercise.workoutSession = session
                context.insert(workoutExercise)

                for setIndex in 0..<4 {
                    let set = WorkoutSet(
                        plannedReps: 10,
                        actualReps: 10,
                        plannedWeight: Double(40 + exerciseIndex),
                        actualWeight: Double(40 + exerciseIndex),
                        restTime: 60,
                        order: setIndex
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
    }
}

@MainActor
private final class MainActorHeartbeat {
    private let clock = ContinuousClock()
    private let interval: Duration

    private(set) var sampleCount = 0
    private(set) var maximumDelay: Duration = .zero

    init(interval: Duration) {
        self.interval = interval
    }

    func run() async {
        while !Task.isCancelled {
            let expectedWake = clock.now.advanced(by: interval)
            do {
                try await clock.sleep(until: expectedWake)
            } catch {
                return
            }

            let delay = expectedWake.duration(to: clock.now)
            sampleCount += 1
            if delay > maximumDelay {
                maximumDelay = delay
            }
        }
    }
}
