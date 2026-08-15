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

    /// The vs-previous comparison's read boundary joins the same tripwire suite.
    ///
    /// Audit P1.6: `ExerciseProgressService.compareWithPrevious` ran on the main actor and
    /// issued one unbounded `FetchDescriptor<WorkoutSession>` with no
    /// `relationshipKeyPathsForPrefetching` **per exercise** — plus two full `Exercise`
    /// library scans per exercise — then faulted every session's exercises and sets one
    /// row at a time. It fired on every workout finish and every past-workout open, with
    /// no opt-in gate. This is the fourth boundary in the suite and the third on the
    /// History actor.
    @Test
    func previousPerformanceLookupKeepsMainActorResponsive() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        // Routine-slot ids matter: without them the resolver falls back to occurrence
        // matching inside a proven routine, which the routine-less seed cannot satisfy,
        // and the case would assert on an empty result.
        let slotIDs = (0..<5).map { _ in UUID() }
        try seedHistory(sessionCount: 240, context: context, routineSlotIDs: slotIDs)

        // Existential on purpose — see the note in the training-snapshot test above.
        let provider: any HistorySnapshotProviding =
            SwiftDataHistorySnapshotProvider(modelContainer: container)
        // An eight-exercise workout: five the user has trained before, three added to the
        // routine since. The three without history are not padding — they are the shape
        // that costs most, because an exercise with no predecessor is only proven absent
        // after every candidate session has been examined, and a real routine gains
        // exercises all the time.
        let trained = slotIDs.enumerated().map { index, slotID in
            PreviousPerformanceLookup.Query(
                workoutExerciseId: UUID(),
                exerciseName: "Exercise \(index)",
                exerciseId: nil,
                loadBehavior: .resistance,
                routineExerciseId: slotID
            )
        }
        let untrained = (0..<3).map { index in
            PreviousPerformanceLookup.Query(
                workoutExerciseId: UUID(),
                exerciseName: "New Exercise \(index)",
                exerciseId: nil,
                loadBehavior: .resistance,
                routineExerciseId: UUID()
            )
        }
        let lookup = PreviousPerformanceLookup(
            // Every seeded session is a candidate; `Date()` here would depend on the
            // wall-clock gap between seeding and asserting.
            before: .distantFuture,
            routineId: nil,
            exercises: trained + untrained
        )
        let heartbeat = MainActorHeartbeat(interval: .milliseconds(10))
        let heartbeatTask = Task { await heartbeat.run() }
        await Task.yield()

        let resolved = try await provider.fetchPreviousPerformances(lookup)

        heartbeatTask.cancel()
        await heartbeatTask.value

        // Only the five trained exercises resolve; the three new ones are absent rather
        // than present-with-no-sets, which is how callers tell "first time" apart.
        #expect(resolved.count == 5)
        // Seeded weight is `40 + exerciseIndex`, so a resolved row proves the scan
        // reached real sets rather than returning an empty dictionary quickly.
        let firstTrained = try #require(trained.first)
        #expect(resolved[firstTrained.workoutExerciseId]?.sets.first?.weight == 40)
        #expect(untrained.allSatisfy { resolved[$0.workoutExerciseId] == nil })
        #expect(
            heartbeat.sampleCount >= 1,
            "the main actor should run while the model actor is resolving previous performances"
        )
        #expect(
            heartbeat.maximumDelay < .milliseconds(100),
            "Previous-performance lookup delayed MainActor by \(heartbeat.maximumDelay)"
        )
    }

    /// §8 placement B's endowed figures join the same tripwire suite.
    ///
    /// The widest read the provider has: it walks *every* completed session's
    /// exercise → set graph with no date window at all. Ticket 11 requires that
    /// this aggregation not run on the main actor, and the requirement is not
    /// theoretical — the value moment fires the instant a workout finishes, i.e.
    /// while the completion screen is dismissing.
    ///
    /// It also pins the numbers themselves, which is the other half of the
    /// ticket: the seed is 240 sessions × 5 exercises × 4 completed sets at
    /// `40 + exerciseIndex` kg × 10 reps, so the totals are arithmetic rather
    /// than whatever the aggregator happens to produce.
    @Test
    func lifetimeTotalsKeepMainActorResponsive() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 240, context: context)

        // Existential on purpose — see the note in the training-snapshot test
        // above. `ProactivePaywallCoordinator` holds
        // `any LifetimeTrainingTotalsProviding`, so the `@concurrent` guarantee
        // has to survive this witness too.
        let provider: any LifetimeTrainingTotalsProviding =
            SwiftDataHistorySnapshotProvider(modelContainer: container)
        let heartbeat = MainActorHeartbeat(interval: .milliseconds(10))
        let heartbeatTask = Task { await heartbeat.run() }
        await Task.yield()

        let totals = try await provider.fetchLifetimeTotals()

        heartbeatTask.cancel()
        await heartbeatTask.value

        #expect(totals.workoutCount == 240)
        #expect(totals.completedSetCount == 240 * 5 * 4)
        // 240 sessions × 4 sets × 10 reps × (40 + 41 + 42 + 43 + 44) kg.
        #expect(totals.volumeKilograms == 240 * 4 * 10 * 210)
        #expect(
            heartbeat.sampleCount >= 1,
            "the main actor should run while the model actor is summing lifetime totals"
        )
        #expect(
            heartbeat.maximumDelay < .milliseconds(100),
            "Lifetime totals work delayed MainActor by \(heartbeat.maximumDelay)"
        )
    }

    /// The trigger question §8 B asks after every workout must agree with the
    /// aggregation without paying for it.
    ///
    /// `fetchCompletedWorkoutCount()` exists because the alternative — deciding
    /// the threshold with `fetchLifetimeTotals()` — put a whole-history walk on
    /// the shared History actor after *every* completion, including the ones
    /// that cannot meet the threshold, in front of the History tab's own
    /// post-workout refetch. This pins that the cheap read is not merely cheaper
    /// but returns the same number.
    @Test
    func completedWorkoutCountAgreesWithTheAggregation() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 40, context: context)
        // An in-progress session must not count: "completed" is `endTime != nil`.
        let running = WorkoutSession(routine: nil)
        running.routineName = "In progress"
        context.insert(running)
        try context.save()

        let provider: any LifetimeTrainingTotalsProviding =
            SwiftDataHistorySnapshotProvider(modelContainer: container)

        let count = try await provider.fetchCompletedWorkoutCount()
        let totals = try await provider.fetchLifetimeTotals()

        #expect(count == 40)
        #expect(count == totals.workoutCount)
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

    /// - Parameter routineSlotIDs: when non-empty, stamps each exercise index with the
    ///   corresponding routine-slot id. Only the previous-performance case needs it, so
    ///   it defaults to off and the other cases keep their exact seeded shape.
    private func seedHistory(
        sessionCount: Int,
        context: ModelContext,
        routineSlotIDs: [UUID] = []
    ) throws {
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
                workoutExercise.routineExerciseId = routineSlotIDs.indices.contains(exerciseIndex)
                    ? routineSlotIDs[exerciseIndex]
                    : nil
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
