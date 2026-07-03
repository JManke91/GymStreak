//
//  SwiftDataWorkoutSessionRepositoryTests.swift
//  GymStreakTests
//
//  Covers SwiftDataWorkoutSessionRepository: the `fetchCompleted` filter and
//  the id/healthKitWorkoutId dedup semantics used by RoutinesViewModel to
//  detect duplicate or retried watch deliveries.
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
    func fetchCompletedOnlyReturnsSessionsWithEndTime() throws {
        let (_, sessions, routines) = makeRepositories()
        let routine = Routine(name: "Push Day")
        routines.insert(routine)

        let completed = WorkoutSession(routine: routine)
        completed.endTime = Date()

        let inProgress = WorkoutSession(routine: routine)
        inProgress.endTime = nil

        sessions.insert(completed)
        sessions.insert(inProgress)
        try sessions.save()

        let result = sessions.fetchCompleted()
        #expect(result.map(\.id) == [completed.id])
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
