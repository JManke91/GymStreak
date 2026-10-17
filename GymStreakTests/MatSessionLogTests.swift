//
//  MatSessionLogTests.swift
//  GymStreakTests
//
//  Logged mat sessions (docs/fight-conditioning.md, "Mat sessions"): the log form's
//  save and Apple Health contract, and the round trip through the app schema.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct MatSessionLogTests {

    // MARK: - Log form

    private func makeLog(
        healthSyncOn: Bool = true,
        saver: RecordingMatSessionWorkoutSaver = RecordingMatSessionWorkoutSaver(),
        now: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    ) -> (MatSessionLogViewModel, SwiftDataMatSessionRepository, RecordingMatSessionWorkoutSaver, ModelContainer) {
        let container = InMemoryModelContainer.make()
        let repository = SwiftDataMatSessionRepository(modelContext: container.mainContext)
        let preference = StubHealthSyncPreference()
        preference.isHealthSyncEnabled = healthSyncOn
        let viewModel = MatSessionLogViewModel(
            sessions: repository,
            workoutSaver: saver,
            healthSync: preference,
            now: now
        )
        return (viewModel, repository, saver, container)
    }

    @Test
    func startFollowsTheDurationUntilTheUserPicksOne() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let (log, _, _, container) = makeLog(now: now)
        _ = container

        log.durationMinutes = 90
        #expect(log.startDate == now.addingTimeInterval(-90 * 60))

        let picked = now.addingTimeInterval(-86_400)
        log.editedStartDate = picked
        log.durationMinutes = 45
        #expect(log.startDate == picked)
    }

    @Test
    func savingWritesTheSessionAndTheHealthWorkoutWithItsId() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let (log, repository, saver, container) = makeLog(now: now)
        _ = container
        log.sport = .boxing
        log.intensity = .hardSparring
        log.durationMinutes = 75
        log.note = "  6 × 3 min rounds  "

        let id = try #require(await log.save())

        let session = try #require(repository.find(id: id))
        #expect(session.sport == .boxing)
        #expect(session.intensity == .hardSparring)
        #expect(session.duration == 75 * 60)
        #expect(session.endTime == now)
        #expect(session.note == "6 × 3 min rounds")
        #expect(session.healthKitWorkoutId == id)
        #expect(saver.saved == [.init(externalUUID: id, sport: .boxing, startDate: session.startTime, endDate: now)])
    }

    @Test
    func withHealthSyncOffTheSessionIsStillSaved() async throws {
        let (log, repository, saver, container) = makeLog(healthSyncOn: false)
        _ = container

        let id = try #require(await log.save())

        let session = try #require(repository.find(id: id))
        #expect(session.healthKitWorkoutId == nil)
        #expect(saver.saved.isEmpty)
    }

    @Test
    func aFailedHealthWriteKeepsTheSession() async throws {
        let saver = RecordingMatSessionWorkoutSaver()
        saver.saveError = HealthKitError.notAuthorized
        let (log, repository, _, container) = makeLog(saver: saver)
        _ = container

        let id = try #require(await log.save())

        let session = try #require(repository.find(id: id))
        #expect(session.healthKitWorkoutId == nil)
    }

    @Test
    func healthActivityTypePerSport() {
        #expect(HealthKitWorkoutManager.configuration(for: .bjj).activityType == .martialArts)
        #expect(HealthKitWorkoutManager.configuration(for: .mma).activityType == .martialArts)
        #expect(HealthKitWorkoutManager.configuration(for: .muayThai).activityType == .martialArts)
        #expect(HealthKitWorkoutManager.configuration(for: .boxing).activityType == .boxing)
        #expect(HealthKitWorkoutManager.configuration(for: .wrestling).activityType == .wrestling)
        #expect(HealthKitWorkoutManager.configuration(for: .other).activityType == .other)
    }

    // MARK: - Persistence

    /// Round-trips through the app schema (which `GymStreakSchema` registers), and
    /// survives a fresh context — not only the in-memory object graph.
    @Test
    func allValuesRoundTripAndDeleteRemovesTheRow() throws {
        let container = InMemoryModelContainer.make()
        let writer = SwiftDataMatSessionRepository(modelContext: ModelContext(container))
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let healthId = UUID()
        let session = MatSession(
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            sport: .muayThai,
            intensity: .drilling,
            note: "Clinch",
            healthKitWorkoutId: healthId
        )
        writer.insert(session)
        try writer.save()

        let reader = SwiftDataMatSessionRepository(modelContext: ModelContext(container))
        let fetched = try #require(reader.find(id: session.id))
        #expect(fetched.startTime == start)
        #expect(fetched.duration == 3_600)
        #expect(fetched.sport == .muayThai)
        #expect(fetched.intensity == .drilling)
        #expect(fetched.note == "Clinch")
        #expect(fetched.healthKitWorkoutId == healthId)

        reader.delete(fetched)
        try reader.save()
        #expect(reader.find(id: session.id) == nil)
    }
}
