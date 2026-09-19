//
//  SwiftDataConditioningRecordRepositoryTests.swift
//  GymStreakTests
//
//  The conditioning history repository (docs/fight-conditioning.md): ordering,
//  lookup by id, delete, and that `ConditioningRecord` really round-trips through
//  the app schema rather than only compiling against it.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// Serialized: see SwiftDataRoutineRepositoryTests for why in-memory ModelContainer
// creation must not run concurrently within this process.
@Suite(.serialized)
@MainActor
struct SwiftDataConditioningRecordRepositoryTests {

    private func makeRepository() -> (context: ModelContext, records: SwiftDataConditioningRecordRepository) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        return (context, SwiftDataConditioningRecordRepository(modelContext: context))
    }

    @discardableResult
    private func insert(
        into repository: SwiftDataConditioningRecordRepository,
        id: UUID = UUID(),
        start: Date,
        duration: TimeInterval = 1_200,
        sessionType: ConditioningSessionDefinition.ID = .lactic30,
        healthKitWorkoutId: UUID? = nil
    ) -> ConditioningRecord {
        let record = ConditioningRecord(
            id: id,
            startTime: start,
            endTime: start.addingTimeInterval(duration),
            sessionTypeRaw: sessionType.rawValue,
            titleSnapshot: "Lactic 30/120",
            energySystemRaw: ConditioningEnergySystem.lactic.rawValue,
            modalityRaw: ConditioningModality.rower.rawValue,
            effortRaw: ConditioningEffort.hardRepeatable.rawValue,
            roundsCompleted: 5,
            roundsPlanned: 6,
            setsPlanned: 0,
            workInterval: 30,
            restInterval: 120,
            endedEarly: true,
            healthKitWorkoutId: healthKitWorkoutId
        )
        repository.insert(record)
        return record
    }

    @Test
    func fetchAllReturnsRecordsNewestFirst() throws {
        let (_, records) = makeRepository()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        insert(into: records, start: base)
        insert(into: records, start: base.addingTimeInterval(86_400))
        insert(into: records, start: base.addingTimeInterval(-86_400))
        try records.save()

        let fetched = records.fetchAll()
        #expect(fetched.count == 3)
        #expect(fetched.map(\.startTime) == fetched.map(\.startTime).sorted(by: >))
    }

    /// Every stored value has to survive the round trip — the whole point of denormalizing
    /// the row is that History can render it without the library.
    @Test
    func allDenormalizedValuesRoundTrip() throws {
        let (_, records) = makeRepository()
        let id = UUID()
        let healthId = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        insert(into: records, id: id, start: start, healthKitWorkoutId: healthId)
        try records.save()

        let found = try #require(records.find(id: id))
        #expect(found.startTime == start)
        #expect(found.duration == 1_200)
        #expect(found.sessionType == .lactic30)
        #expect(found.energySystem == .lactic)
        #expect(found.modality == .rower)
        #expect(found.effort == .hardRepeatable)
        #expect(found.roundsCompleted == 5)
        #expect(found.roundsPlanned == 6)
        #expect(found.workInterval == 30)
        #expect(found.restInterval == 120)
        #expect(found.endedEarly)
        #expect(found.healthKitWorkoutId == healthId)
        #expect(!found.isSteadyState)
    }

    @Test
    func findReturnsNilForAnUnknownId() throws {
        let (_, records) = makeRepository()
        insert(into: records, start: Date())
        try records.save()

        #expect(records.find(id: UUID()) == nil)
    }

    @Test
    func deleteRemovesTheRecord() throws {
        let (_, records) = makeRepository()
        let id = UUID()
        let record = insert(into: records, id: id, start: Date())
        insert(into: records, start: Date().addingTimeInterval(-3_600))
        try records.save()

        records.delete(record)
        try records.save()

        #expect(records.find(id: id) == nil)
        #expect(records.fetchAll().count == 1)
    }

    /// A steady-state session has no rounds, and that is how the card decides not to print any.
    @Test
    func steadyStateRecordsReportNoRounds() throws {
        let (_, records) = makeRepository()
        let id = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let record = ConditioningRecord(
            id: id,
            startTime: start,
            endTime: start.addingTimeInterval(2_700),
            sessionTypeRaw: ConditioningSessionDefinition.ID.aerobicBase.rawValue,
            titleSnapshot: "Aerobic base",
            energySystemRaw: ConditioningEnergySystem.aerobic.rawValue,
            modalityRaw: ConditioningModality.run.rawValue,
            effortRaw: ConditioningEffort.conversational.rawValue,
            roundsCompleted: 0,
            roundsPlanned: 0,
            setsPlanned: 0,
            workInterval: 0,
            restInterval: 0,
            endedEarly: false
        )
        records.insert(record)
        try records.save()

        let found = try #require(records.find(id: id))
        #expect(found.isSteadyState)
        #expect(found.duration == 2_700)
    }
}
