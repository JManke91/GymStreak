//
//  WatchConditioningIngestorTests.swift
//  GymStreakTests
//
//  Ticket 07 (docs/fight-conditioning.md): a conditioning session finished on
//  the watch becomes exactly one History record — however often WatchConnectivity
//  delivers it, and never again once the user deleted it — carries the watch's
//  Apple Health id only when the watch saved that workout, and counts towards the
//  program week like a session run on the phone.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

private struct EmptyProgramCloud: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? { nil }
    func set(_ data: Data, forKey key: String) {}
}

// Serialized: in-memory ModelContainer creation must not run concurrently
// (see SwiftDataRoutineRepositoryTests).
@Suite(.serialized) @MainActor
struct WatchConditioningIngestorTests {

    private func makeIngestor() -> (WatchConditioningIngestor, SwiftDataConditioningRecordRepository, ModelContainer) {
        let container = InMemoryModelContainer.make()
        let records = SwiftDataConditioningRecordRepository(modelContext: container.mainContext)
        let ingestor = WatchConditioningIngestor(records: records, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (ingestor, records, container)
    }

    private func session(
        id: UUID = UUID(),
        type: ConditioningSessionDefinition.ID = .lactic30,
        start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000),
        isSavedToHealth: Bool = true
    ) -> WatchCompletedConditioningSession {
        let definition = ConditioningLibrary.session(type)
        return WatchCompletedConditioningSession(
            id: id, startTime: start, endTime: start.addingTimeInterval(1_500),
            sessionType: type.rawValue, title: "Lactic 30/120",
            energySystem: definition.energySystem.rawValue, modality: ConditioningModality.rower.rawValue,
            effort: ConditioningEffort.hardRepeatable.rawValue,
            roundsCompleted: 5, roundsPlanned: 6, setsPlanned: 0, workInterval: 30, restInterval: 120,
            endedEarly: true, isSavedToHealth: isSavedToHealth
        )
    }

    @Test("Duplicate deliveries produce one record")
    func duplicatesProduceOneRecord() {
        let (ingestor, records, container) = makeIngestor()
        _ = container
        let delivery = session()
        #expect(ingestor.ingest(delivery) == .inserted)
        #expect(ingestor.ingest(delivery) == .duplicate)
        #expect(ingestor.ingest(delivery) == .duplicate)
        #expect(records.fetchAll().count == 1)
    }

    @Test("A redelivery after the user deleted the session does not bring it back")
    func deletedSessionIsNotResurrected() throws {
        let (ingestor, records, container) = makeIngestor()
        _ = container
        let delivery = session()
        #expect(ingestor.ingest(delivery) == .inserted)
        records.delete(try #require(records.find(id: delivery.id)))
        try records.save()

        #expect(ingestor.ingest(delivery) == .duplicate)
        #expect(records.fetchAll().isEmpty)
    }

    @Test("A session already in History (e.g. via iCloud) is acknowledged, not duplicated")
    func existingRecordIsDuplicate() throws {
        let (ingestor, records, container) = makeIngestor()
        _ = container
        let delivery = session()
        records.insert(WatchConditioningMapper.record(from: delivery))
        try records.save()
        #expect(ingestor.ingest(delivery) == .duplicate)
        #expect(records.fetchAll().count == 1)
    }

    @Test("The record copies the watch's numbers; the Health id only when the watch saved the workout")
    func recordMapping() throws {
        let (ingestor, records, container) = makeIngestor()
        _ = container
        let saved = session()
        let unsaved = session(isSavedToHealth: false)
        _ = ingestor.ingest(saved)
        _ = ingestor.ingest(unsaved)

        let record = try #require(records.find(id: saved.id))
        #expect(record.healthKitWorkoutId == saved.id)
        #expect(record.sessionType == .lactic30)
        #expect(record.energySystem == .lactic)
        #expect(record.modality == .rower)
        #expect(record.roundsCompleted == 5)
        #expect(record.roundsPlanned == 6)
        #expect(record.restInterval == 120)
        #expect(record.endedEarly)
        #expect(record.duration == 1_500)
        #expect(try #require(records.find(id: unsaved.id)).healthKitWorkoutId == nil)
    }

    @Test("A watch-logged session counts towards the program week")
    func countsTowardsProgramWeek() throws {
        let calendar = ProgramTestCalendar.make()
        let now = ProgramTestCalendar.date(2026, 9, 23, 18)
        let container = InMemoryModelContainer.make()
        let records = SwiftDataConditioningRecordRepository(modelContext: container.mainContext)
        let program = ConditioningProgramViewModel(
            store: ConditioningProgramStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!,
                cloud: EmptyProgramCloud(),
                observesExternalChanges: false
            ),
            conditioningRecords: records,
            workoutSessions: SwiftDataWorkoutSessionRepository(modelContext: container.mainContext),
            calendar: calendar,
            now: { now }
        )
        program.enroll(startDate: ProgramTestCalendar.date(2026, 9, 21), experience: .beginner, sparsHard: false)
        let target = try #require(program.dashboard?.progress.first)
        #expect(target.completed == 0)

        let ingestor = WatchConditioningIngestor(records: records, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        _ = ingestor.ingest(session(type: target.id, start: now.addingTimeInterval(-3_600)))
        program.refresh()

        #expect(program.dashboard?.progress.first { $0.id == target.id }?.completed == 1)
    }
}
