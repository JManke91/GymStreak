//
//  HistoryGateLatencyTests.swift
//  GymStreakTests
//
//  What the History gate costs the user, measured rather than argued.
//
//  `HistoryStoreGate.acquire` is exclusive, strictly FIFO and deliberately **not**
//  cancellation-aware, and it serializes three `@ModelActor` readers plus the watch
//  ingestion drain against every writer that can delete a row those readers hold. So a
//  delete tapped in History can wait behind reads nobody is looking at any more. That
//  trade is argued in `acquire`'s own comment; this suite is where the number behind it
//  comes from (docs/history-delete-race.md, "What the gate costs — measured").
//
//  The fixture is the store that actually crashed, rebuilt on disk at 343 `WorkoutExercise`
//  rows with the full starter catalog and four scheduled routines — see
//  `HistoryGateLatencyHarness`, which also holds the stopwatch and explains why the waits
//  are staged behind a stand-in holder rather than raced. Each number is the **worst case**
//  for its shape: the write arriving at the instant the fan-out starts. A tap landing
//  halfway through a rebuild waits about half as long.
//
//  The `#expect` ceilings are deliberately loose. They are regression tripwires for someone
//  putting a new unbounded read under the gate, not the measurement: the numbers themselves
//  are printed (grep the test log for `GATE-COST`) and recorded in the doc.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
struct HistoryGateLatencyTests {

    /// What each gated read costs on its own — the units every wait below is made of.
    @Test
    @MainActor
    func readCostsAtTheCrashStoreVolume() async throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let context = ModelContext(container)
        let fixture = try HistoryGateLatencyHarness.seed(into: context)
        try HistoryGateLatencyHarness.verifyFixtureShape(context)

        // Concrete provider types on purpose, unlike `SwiftDataHistorySnapshotStoreTests`:
        // that suite uses existentials because the `@concurrent` guarantee has to survive
        // the witness, which is what it is testing. Here the subject is elapsed time, and
        // the concrete type is what `AppDependencies` constructs.
        let gate = HistoryStoreGate()
        let history = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: gate)
        let chat = ChatFactProvider(modelContainer: container, gate: gate)
        let attribution = SwiftDataLegacyHistoryAttributionProvider(modelContainer: container, gate: gate)
        let trainedName = fixture.trainedExerciseNames[0]

        // Cold — the model actors are built lazily behind a `Task.detached`, and the first
        // read pays for that plus SQLite's first page reads. That is what the user pays on
        // the first History open too.
        let snapshot = try await HistoryGateLatencyHarness.measure("fetchTrainingSnapshot (cold)") {
            try await history.fetchTrainingSnapshot(referenceDate: Date())
        }
        #expect(snapshot.sessionCount == HistoryGateLatencyHarness.sessionCount)

        _ = try await HistoryGateLatencyHarness.measure("fetchTrainingSnapshot (warm)") {
            try await history.fetchTrainingSnapshot(referenceDate: Date())
        }
        _ = try await HistoryGateLatencyHarness.measure("fetchFortschrittSnapshot") {
            try await history.fetchFortschrittSnapshot()
        }
        _ = try await HistoryGateLatencyHarness.measure("fetchLifetimeTotals") {
            try await history.fetchLifetimeTotals()
        }
        _ = try await HistoryGateLatencyHarness.measure("fetchCompletedWorkoutCount") {
            try await history.fetchCompletedWorkoutCount()
        }
        _ = try await HistoryGateLatencyHarness.measure("fetchExerciseProgress") {
            try await history.fetchExerciseProgress(
                exerciseName: trainedName,
                exerciseId: fixture.trainedExerciseIDs[0],
                startDate: .distantPast,
                recentSessionLimit: 8,
                usageSelection: nil
            )
        }
        _ = await HistoryGateLatencyHarness.measure("ChatFactProvider.nextWorkoutFacts") {
            await chat.nextWorkoutFacts()
        }
        _ = await HistoryGateLatencyHarness.measure("ChatFactProvider.exercisePRFacts") {
            await chat.exercisePRFacts(exerciseName: trainedName, weightUnit: .kilograms)
        }
        _ = await HistoryGateLatencyHarness.measure("ChatFactProvider.workoutHistoryFacts(.allTime)") {
            await chat.workoutHistoryFacts(timeframe: .allTime, weightUnit: .kilograms)
        }
        // Nothing to repair in this fixture — every row carries its `exerciseId`, as every
        // shipped write path has. This is the cost of the *fetch*, which is what a queued
        // writer waits for regardless of whether the repair finds work.
        _ = try await HistoryGateLatencyHarness.measure("attributeLegacyRows (no legacy rows)") {
            try await attribution.attributeLegacyRows(
                named: trainedName,
                to: fixture.trainedExerciseIDs[0]
            )
        }
    }

    /// The worst case the ticket asks for: a delete tapped at the instant a full read
    /// fan-out starts, so it waits for every one of them before a row leaves the screen.
    ///
    /// The fan-out is everything that can hold the gate at once on a real device: the
    /// History tab's two loads, the proactive-paywall totals, a coach turn's three fact
    /// lookups, and the legacy-attribution repair. It is an upper bound by construction —
    /// no single screen triggers all eight — which is exactly what "worst case" means here.
    @Test
    @MainActor
    func deleteWaitsBehindTheFullReadFanOut() async throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let context = ModelContext(container)
        let fixture = try HistoryGateLatencyHarness.seed(into: context)

        let gate = HistoryStoreGate()
        let viewModel = HistoryGateLatencyHarness.makeViewModel(context: context, gate: gate)
        let repository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let doomed = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let doomedID = doomed.id

        let result = await HistoryGateLatencyHarness.measureWriteBehind(
            fanOut: Self.fullReadFanOut(container: container, gate: gate, fixture: fixture),
            gate: gate
        ) {
            await viewModel.deleteWorkout(doomed)
        }

        HistoryGateLatencyHarness.report("History delete behind the full read fan-out", result.wait)
        #expect(repository.findSession(id: doomedID, healthKitWorkoutId: nil) == nil)
        #expect(result.writeWentLast, "the delete did not queue last: \(result.completionOrder)")
        // Loose on purpose: one device run in eight came in ~4x slower across the board
        // (3.2 s here), and this machine routinely has parallel builds on it. A tripwire
        // that fires on load would be worse than no tripwire.
        #expect(
            result.wait < .seconds(10),
            "a History delete waited \(result.wait) behind the read fan-out — a new unbounded read under the gate?"
        )
    }

    /// The shipped scenario, and the one a user actually reproduces: two deletes in a row.
    /// The first one's `refreshHistory()` starts a rebuild, and the second delete queues
    /// behind it — the exact 00:19:10 / 00:19:14 pair that crashed the app before the gate
    /// existed, and now the pair that makes a row linger instead.
    @Test
    @MainActor
    func secondDeleteWaitsBehindTheRebuildTheFirstOneTriggered() async throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let context = ModelContext(container)
        _ = try HistoryGateLatencyHarness.seed(into: context)

        let gate = HistoryStoreGate()
        let history = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: gate)
        let viewModel = HistoryGateLatencyHarness.makeViewModel(context: context, gate: gate)
        let repository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let doomed = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let doomedID = doomed.id

        let result = await HistoryGateLatencyHarness.measureWriteBehind(
            fanOut: [{ _ = try? await history.fetchTrainingSnapshot(referenceDate: Date()) }],
            gate: gate
        ) {
            await viewModel.deleteWorkout(doomed)
        }

        HistoryGateLatencyHarness.report("History delete behind one rebuild", result.wait)
        #expect(repository.findSession(id: doomedID, healthKitWorkoutId: nil) == nil)
        #expect(result.writeWentLast, "the delete did not queue behind the rebuild")
        // A floor as well as a ceiling: without it a delete that won the race to `acquire()`
        // would pass with a number that measures nothing.
        #expect(
            result.wait > .milliseconds(20),
            "the delete did not actually wait for the rebuild (\(result.wait))"
        )
        #expect(
            result.wait < .seconds(5),
            "a second History delete waited \(result.wait) behind one rebuild"
        )
    }

    /// The wait `HistoryStoreGate.acquire`'s own comment admits to, and the one the ticket
    /// asks about: `acquire` is deliberately not cancellation-aware, so a rebuild that
    /// `.task(id:)` has already superseded still takes its FIFO turn ahead of a queued
    /// delete.
    ///
    /// It turns out to cost almost nothing. Every `SwiftDataHistorySnapshotStore` method
    /// checks cancellation as its first statement, so a cancelled reader that finally gets
    /// the gate returns before it fetches anything and releases it again — the delete pays
    /// for the hand-off, not for a walk. That is the measurement behind "accepted on
    /// purpose": making `acquire` cancellation-aware would buy back this number, not a
    /// rebuild.
    ///
    /// It does **not** generalize to every reader: `ChatFactStore` has no cancellation
    /// checks at all, so a cancelled coach fact lookup does pay in full.
    @Test
    @MainActor
    func aCancelledRebuildQueuedAheadOfADeleteCostsAlmostNothing() async throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let context = ModelContext(container)
        _ = try HistoryGateLatencyHarness.seed(into: context)

        let gate = HistoryStoreGate()
        let history = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: gate)
        let viewModel = HistoryGateLatencyHarness.makeViewModel(context: context, gate: gate)
        let repository = SwiftDataWorkoutSessionRepository(modelContext: context)
        let doomed = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let doomedID = doomed.id

        let result = await HistoryGateLatencyHarness.measureWriteBehind(
            fanOut: [{ _ = try? await history.fetchTrainingSnapshot(referenceDate: Date()) }],
            cancelFanOutOnceQueued: true,
            gate: gate
        ) {
            await viewModel.deleteWorkout(doomed)
        }

        HistoryGateLatencyHarness.report("History delete behind a CANCELLED rebuild", result.wait)
        #expect(repository.findSession(id: doomedID, healthKitWorkoutId: nil) == nil)
        // Load-bearing: the claim is "the reader was ahead in the queue and handed the gate
        // on cheaply". A delete that simply won the race would produce the same 5 ms for
        // entirely the wrong reason.
        #expect(
            result.writeWentLast,
            "the delete did not queue behind the cancelled rebuild: \(result.completionOrder)"
        )
        #expect(
            result.wait < .milliseconds(50),
            "a cancelled rebuild cost the queued delete \(result.wait) — did a reader stop checking cancellation?"
        )
    }

    /// The other user-visible wait: an edit inside a workout that has already been finished.
    ///
    /// `pauseForCompletion()` persists `endTime` the moment the last set is completed, while
    /// the session stays `currentSession` and fully editable — so from then on every set
    /// deletion routes through the gate (`withHistoryGateIfVisible`). This is the same
    /// removal a user makes on the completion screen, timed behind a rebuild.
    @Test
    @MainActor
    func inWorkoutSetDeleteOnAFinishedSessionWaitsBehindARebuild() async throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let context = ModelContext(container)
        _ = try HistoryGateLatencyHarness.seed(into: context)

        let gate = HistoryStoreGate()
        let history = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: gate)
        let viewModel = HistoryGateLatencyHarness.makeViewModel(context: context, gate: gate)

        // The newest session, still open on screen exactly as `pauseForCompletion()` leaves
        // it: `endTime` saved, `currentSession` set, editable.
        let session = try #require(
            try context.fetch(
                FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
            ).first
        )
        viewModel.currentSession = session
        let exercise = try #require(session.workoutExercisesList.first)
        let set = try #require(exercise.setsList.first)
        let setID = set.id

        let result = await HistoryGateLatencyHarness.measureWriteBehind(
            fanOut: [{ _ = try? await history.fetchTrainingSnapshot(referenceDate: Date()) }],
            gate: gate
        ) {
            await viewModel.removeSetFromExercise(set, from: exercise)
        }

        HistoryGateLatencyHarness.report(
            "In-workout set delete (finished session) behind one rebuild",
            result.wait
        )
        #expect(exercise.setsList.contains { $0.id == setID } == false)
        #expect(result.writeWentLast, "the edit did not queue behind the rebuild")
        #expect(
            result.wait > .milliseconds(20),
            "the edit did not actually wait for the rebuild (\(result.wait))"
        )
        #expect(
            result.wait < .seconds(5),
            "an in-workout edit on a finished session waited \(result.wait) behind one rebuild"
        )
    }

    /// Everything that can be holding or queued on the gate at the moment a delete is
    /// tapped. Order matters only in that the write goes last.
    @MainActor
    private static func fullReadFanOut(
        container: ModelContainer,
        gate: HistoryStoreGate,
        fixture: HistoryGateLatencyHarness.Fixture
    ) -> [@Sendable () async -> Void] {
        let history = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: gate)
        let chat = ChatFactProvider(modelContainer: container, gate: gate)
        let attribution = SwiftDataLegacyHistoryAttributionProvider(modelContainer: container, gate: gate)
        let name = fixture.trainedExerciseNames[0]
        let id = fixture.trainedExerciseIDs[0]

        return [
            { _ = try? await history.fetchTrainingSnapshot(referenceDate: Date()) },
            { _ = try? await history.fetchFortschrittSnapshot() },
            { _ = try? await history.fetchLifetimeTotals() },
            { _ = try? await history.fetchCompletedWorkoutCount() },
            { _ = await chat.nextWorkoutFacts() },
            { _ = await chat.exercisePRFacts(exerciseName: name, weightUnit: .kilograms) },
            { _ = await chat.workoutHistoryFacts(timeframe: .allTime, weightUnit: .kilograms) },
            { _ = try? await attribution.attributeLegacyRows(named: name, to: id) }
        ]
    }
}
