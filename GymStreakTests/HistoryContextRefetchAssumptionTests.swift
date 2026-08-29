//
//  HistoryContextRefetchAssumptionTests.swift
//  GymStreakTests
//
//  The load-bearing SwiftData assumption underneath the whole History gate design.
//
//  `HistoryStoreGate` makes a delete and a rebuild mutually exclusive. That is only
//  *sufficient* — rather than merely necessary — because the reader re-runs its fetches
//  every pass and thereby sees the current graph. The History `@ModelActor`'s
//  `ModelContext` is created once and lives for the entire app session: never reset,
//  never rolled back. If such a context instead accumulated stale registered objects and
//  stale materialized to-many relationships between locked sections, a mutex would not be
//  enough and the fix would have to be a fresh `ModelContext(container)` per read.
//
//  That behaviour was established **empirically** during the delete-race investigation
//  (`docs/history-delete-race.md`, "Confirmed by experiment"), not from an Apple guarantee.
//  Apple documents the opposite for the generic refresh path — "refreshing an object will
//  not refresh its relationships" — and what this codebase relies on comes from
//  `relationshipKeyPathsForPrefetching` re-issuing a live join query in
//  `CompletedSessionFetch.withFullGraph`. An OS update could change it and every other
//  test in the suite would still pass. Hence these two.
//
//  **How these tests fail.** Ideally with a red assertion: the second walk still reporting
//  the pre-delete counts means the re-fetch handed back a stale graph. But a stale
//  *relationship* cache pointing at deleted rows fails harder — SwiftData traps in
//  `BackingData.swift:1039` ("This model instance was invalidated…"), an uncatchable
//  `fatalError` that kills the test runner. A crashed run is equally this test failing.
//
//  **Either failure means the same thing:** serialization alone is no longer sufficient,
//  and every History reader has to take a fresh `ModelContext` per pass instead of reusing
//  the model actor's.
//
//  The investigation's third case — a delete landing *mid-walk*, over objects the reader
//  is already holding — is the shipped crash and is deliberately **not** reproduced here;
//  it traps by design and would take every other test down with it. Both cases below were
//  verified to pass and are safe to keep because neither traps. `HistoryStoreGateTests`
//  asserts the gate's properties, and `HistoryDeleteRaceRegressionTests` drives the real
//  reader against the real writer.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
struct HistoryContextRefetchAssumptionTests {

    /// Counts of what one full walk of the completed-workout graph actually reached.
    private struct WalkResult: Equatable {
        var sessions = 0
        var exercises = 0
        var sets = 0
    }

    @Test
    @MainActor
    func aWholeSessionDeletedBetweenWalksLeavesTheReaderContextWithTheReducedGraph() async throws {
        // On-disk, not in-memory: an in-memory store does not fault the same way, so it
        // does not exercise the behaviour under test at all.
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }

        // Two contexts over one store, exactly as the app runs them: `readerContext`
        // stands in for the History `@ModelActor`'s long-lived context and is never reset
        // between the two walks; `writerContext` stands in for the main-actor context that
        // commits the delete.
        let readerContext = ModelContext(container)
        let writerContext = ModelContext(container)

        try Self.seedCompletedGraph(sessionCount: 3, into: writerContext)

        let before = try Self.walkFullGraph(in: readerContext)
        #expect(before == WalkResult(sessions: 3, exercises: 6, sets: 18))

        let doomed = try #require(
            try writerContext.fetch(FetchDescriptor<WorkoutSession>()).first
        )
        writerContext.delete(doomed)
        try writerContext.save()

        // The whole point: the same context walks again, without being reset or rolled
        // back, and must see the store as it now is.
        let after = try Self.walkFullGraph(in: readerContext)
        #expect(after == WalkResult(sessions: 2, exercises: 4, sets: 12))
    }

    @Test
    @MainActor
    func aSingleSetDeletedUnderSurvivingParentsLeavesNoStaleRelationship() async throws {
        // The sharper case. When the whole session goes, the re-fetch simply returns fewer
        // top-level rows and the reader never has to look at a previously registered
        // parent. Here the parent exercise and session both survive the delete, so the
        // re-fetch hands back objects the context already holds — and their `sets`
        // relationship was materialized by the first walk. If any stale to-many cache
        // survives a re-fetch, this is where it shows.
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }

        let readerContext = ModelContext(container)
        let writerContext = ModelContext(container)

        try Self.seedCompletedGraph(sessionCount: 2, into: writerContext)

        let before = try Self.walkFullGraph(in: readerContext)
        #expect(before == WalkResult(sessions: 2, exercises: 4, sets: 12))

        let doomed = try #require(
            try writerContext.fetch(FetchDescriptor<WorkoutSet>()).first
        )
        let survivingExerciseID = try #require(doomed.workoutExercise?.id)
        writerContext.delete(doomed)
        try writerContext.save()

        let after = try Self.walkFullGraph(in: readerContext)
        #expect(after == WalkResult(sessions: 2, exercises: 4, sets: 11))

        // And the parent specifically — not just the total — must report the reduced
        // collection, so a stale cache cannot hide behind a coincidental count.
        let parent = try #require(
            try readerContext.fetch(FetchDescriptor<WorkoutExercise>())
                .first(where: { $0.id == survivingExerciseID })
        )
        #expect(parent.setsList.count == 2)
    }

    // MARK: - Walk

    /// Runs the production fetch and then reads every property the History builders read,
    /// which is what forces the relationships to materialize in `context`.
    ///
    /// Deliberately returns only counts: no `@Model` object escapes this function, so the
    /// next walk starts from nothing but the context's own registry — which is precisely
    /// the state whose freshness is being asserted. Retaining the objects across the delete
    /// instead would be the shipped crash, not this test.
    @MainActor
    private static func walkFullGraph(in context: ModelContext) throws -> WalkResult {
        var result = WalkResult()
        for session in try CompletedSessionFetch.withFullGraph(in: context) {
            _ = session.routineName
            _ = session.endTime
            _ = session.routine?.id
            result.sessions += 1
            for exercise in session.workoutExercisesList {
                _ = exercise.exerciseName
                _ = exercise.muscleGroups
                result.exercises += 1
                for set in exercise.setsList {
                    _ = set.actualReps
                    _ = set.actualWeight
                    _ = set.isCompleted
                    result.sets += 1
                }
            }
        }
        return result
    }

    // MARK: - Fixture

    @MainActor
    private static func seedCompletedGraph(sessionCount: Int, into context: ModelContext) throws {
        for sessionIndex in 0..<sessionCount {
            let session = WorkoutSession(routine: nil)
            session.routineName = "Refetch \(sessionIndex)"
            // `endTime != nil` is what both History fetches select on — without it these
            // rows are invisible to `withFullGraph` and the walk would count nothing.
            session.endTime = session.startTime.addingTimeInterval(3600)
            context.insert(session)

            for order in 0..<2 {
                let exercise = WorkoutExercise(
                    exerciseName: "Exercise \(order)",
                    muscleGroups: ["Chest"],
                    order: order,
                    exerciseId: UUID(),
                    routineExerciseId: UUID(),
                    loadBehavior: .resistance
                )
                exercise.workoutSession = session
                context.insert(exercise)

                for setOrder in 0..<3 {
                    let set = WorkoutSet(
                        plannedReps: 8,
                        actualReps: 8,
                        plannedWeight: 60,
                        actualWeight: 60,
                        restTime: 90,
                        order: setOrder
                    )
                    set.isCompleted = true
                    set.workoutExercise = exercise
                    context.insert(set)
                }
            }
        }
        try context.save()
    }
}
