//
//  SwiftDataWorkoutSessionRepositoryTests.swift
//  GymStreakTests
//
//  Covers SwiftDataWorkoutSessionRepository: the id/healthKitWorkoutId dedup
//  semantics used by RoutinesViewModel to detect duplicate or retried watch
//  deliveries, and the bounded per-routine `lastCompletedStartDates` query that
//  replaced a whole-history scan.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory ModelContainer
// creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct SwiftDataWorkoutSessionRepositoryTests {

    private func makeRepositories() -> (
        context: ModelContext,
        sessions: SwiftDataWorkoutSessionRepository,
        routines: SwiftDataRoutineRepository
    ) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        return (
            context,
            SwiftDataWorkoutSessionRepository(modelContext: context),
            SwiftDataRoutineRepository(modelContext: context)
        )
    }

    @Test
    func findSessionMatchesByPrimaryId() throws {
        let (_, sessions, routines) = makeRepositories()
        let routine = Routine(name: "Push Day")
        routines.insert(routine)
        let session = WorkoutSession(routine: routine)
        sessions.insert(session)
        try sessions.save()

        let found = sessions.findSession(id: session.id, healthKitWorkoutId: nil)
        #expect(found?.id == session.id)
    }

    @Test
    func findSessionMatchesByHealthKitIdWhenPrimaryIdDiffers() throws {
        // Simulates a session reconstructed from HealthKit (different local id)
        // being matched against the real watch payload's healthKitWorkoutId.
        let (_, sessions, routines) = makeRepositories()
        let routine = Routine(name: "Push Day")
        routines.insert(routine)
        let healthKitId = UUID()
        let session = WorkoutSession(routine: routine)
        session.healthKitWorkoutId = healthKitId
        sessions.insert(session)
        try sessions.save()

        let found = sessions.findSession(id: UUID(), healthKitWorkoutId: healthKitId)
        #expect(found?.id == session.id)
    }

    @Test
    func findSessionReturnsNilWhenNoMatch() {
        let (_, sessions, _) = makeRepositories()
        let found = sessions.findSession(id: UUID(), healthKitWorkoutId: UUID())
        #expect(found == nil)
    }

    @Test
    func lastCompletedStartDatesReturnsTheNewestCompletedSessionPerRoutine() throws {
        let (_, sessions, routines) = makeRepositories()
        let push = Routine(name: "Push Day")
        let pull = Routine(name: "Pull Day")
        routines.insert(push)
        routines.insert(pull)

        let older = WorkoutSession(routine: push)
        older.startTime = Date(timeIntervalSince1970: 1_000)
        older.endTime = Date(timeIntervalSince1970: 2_000)

        let newest = WorkoutSession(routine: push)
        newest.startTime = Date(timeIntervalSince1970: 5_000)
        newest.endTime = Date(timeIntervalSince1970: 6_000)

        let otherRoutine = WorkoutSession(routine: pull)
        otherRoutine.startTime = Date(timeIntervalSince1970: 3_000)
        otherRoutine.endTime = Date(timeIntervalSince1970: 4_000)

        for session in [older, newest, otherRoutine] { sessions.insert(session) }
        try sessions.save()

        let dates = sessions.lastCompletedStartDates(forRoutineIds: [push.id, pull.id])
        #expect(dates[push.id] == newest.startTime)
        #expect(dates[pull.id] == otherRoutine.startTime)
    }

    @Test
    func lastCompletedStartDatesIgnoresSessionsWithNoRoutine() throws {
        // Orphaned history is a first-class case: a session whose routine was
        // deleted keeps its denormalized copy but loses the relationship. It must
        // not be attributed to any routine.
        let (_, sessions, routines) = makeRepositories()
        let routine = Routine(name: "Push Day")
        routines.insert(routine)

        let orphaned = WorkoutSession(routine: nil)
        orphaned.startTime = Date(timeIntervalSince1970: 9_000)
        orphaned.endTime = Date(timeIntervalSince1970: 9_500)

        let attributed = WorkoutSession(routine: routine)
        attributed.startTime = Date(timeIntervalSince1970: 1_000)
        attributed.endTime = Date(timeIntervalSince1970: 2_000)

        sessions.insert(orphaned)
        sessions.insert(attributed)
        try sessions.save()

        let dates = sessions.lastCompletedStartDates(forRoutineIds: [routine.id])
        #expect(dates[routine.id] == attributed.startTime)
        #expect(dates.count == 1)
    }

    @Test
    func lastCompletedStartDatesIgnoresInProgressSessionsAndUnaskedRoutines() throws {
        let (_, sessions, routines) = makeRepositories()
        let push = Routine(name: "Push Day")
        let untrained = Routine(name: "Leg Day")
        let notAskedAbout = Routine(name: "Pull Day")
        routines.insert(push)
        routines.insert(untrained)
        routines.insert(notAskedAbout)

        // Newer than the completed one, but still running — must not win.
        let inProgress = WorkoutSession(routine: push)
        inProgress.startTime = Date(timeIntervalSince1970: 9_000)
        inProgress.endTime = nil

        let completed = WorkoutSession(routine: push)
        completed.startTime = Date(timeIntervalSince1970: 1_000)
        completed.endTime = Date(timeIntervalSince1970: 2_000)

        let excluded = WorkoutSession(routine: notAskedAbout)
        excluded.startTime = Date(timeIntervalSince1970: 8_000)
        excluded.endTime = Date(timeIntervalSince1970: 8_500)

        for session in [inProgress, completed, excluded] { sessions.insert(session) }
        try sessions.save()

        let dates = sessions.lastCompletedStartDates(
            forRoutineIds: [push.id, untrained.id]
        )
        #expect(dates[push.id] == completed.startTime)
        // A routine that was never completed simply has no entry.
        #expect(dates[untrained.id] == nil)
        // Routines outside the requested set are never queried.
        #expect(dates[notAskedAbout.id] == nil)
        #expect(dates.count == 1)
    }

    @Test
    func insertAndDeleteRoundTrip() throws {
        let (_, sessions, routines) = makeRepositories()
        let routine = Routine(name: "Push Day")
        routines.insert(routine)
        let session = WorkoutSession(routine: routine)

        sessions.insert(session)
        try sessions.save()
        #expect(sessions.findSession(id: session.id, healthKitWorkoutId: nil) != nil)

        sessions.delete(session)
        try sessions.save()
        #expect(sessions.findSession(id: session.id, healthKitWorkoutId: nil) == nil)
    }
}
