//
//  WatchMatSessionIngestTests.swift
//  GymStreakTests
//
//  Positioning ticket 05 (docs/fight-conditioning.md, "Mat sessions on the
//  watch"): the iPhone's half. The heart-rate bands the watch suggests an
//  intensity from, their trip on the conditioning offer whatever the program
//  state, and a watch mat session becoming exactly one `MatSession` — the same
//  record type the iPhone logs — that never counts toward the program.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

// Serialized: in-memory ModelContainer creation must not run concurrently
// (see SwiftDataRoutineRepositoryTests).
@Suite(.serialized) @MainActor
struct WatchMatSessionIngestTests {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Bands

    @Test("Bands from % of max: moderate from the aerobic top (75 %), hard from 85 %")
    func bandsFromMax() throws {
        // Age 40 → HRmax 180.
        let zones = try #require(HeartRateZones.matIntensityZones(for: HeartRateProfile(age: 40)))
        #expect(zones == MatIntensityZones(moderateFromBPM: 135, hardFromBPM: 153))
    }

    @Test("Bands from heart-rate reserve when resting is known: 70 % and 80 % of reserve")
    func bandsFromReserve() throws {
        // 180 max, 60 resting → reserve 120.
        let zones = try #require(HeartRateZones.matIntensityZones(for: HeartRateProfile(age: 40, restingHeartRate: 60)))
        #expect(zones == MatIntensityZones(moderateFromBPM: 144, hardFromBPM: 156))
    }

    @Test("No bands without a usable profile or with the medication switch")
    func noBands() {
        #expect(HeartRateZones.matIntensityZones(for: nil) == nil)
        #expect(HeartRateZones.matIntensityZones(for: HeartRateProfile()) == nil)
        #expect(HeartRateZones.matIntensityZones(for: HeartRateProfile(age: 40, usesHeartRateMedication: true)) == nil)
    }

    @Test("The bands ride the offer even when the user is not enrolled, and reach the wire")
    func bandsRideTheEmptyOffer() throws {
        let calendar = ProgramTestCalendar.make()
        let now = ProgramTestCalendar.date(2026, 10, 17, 9)
        let offer = ConditioningProgramViewModel.watchOffer(
            dashboard: nil,
            today: ConditioningProgramDay(now, calendar: calendar),
            profile: HeartRateProfile(age: 40),
            calendar: calendar,
            now: now
        )
        #expect(offer.sessions.isEmpty)
        let wire = WatchConditioningMapper.program(from: offer)
        #expect(wire.matIntensityZones == WatchMatIntensityZones(moderateFromBPM: 135, hardFromBPM: 153))
        #expect(WatchConditioningWire.decode(try #require(WatchConditioningWire.encode(wire))) == wire)

        let withoutProfile = ConditioningProgramViewModel.watchOffer(
            dashboard: nil, today: ConditioningProgramDay(now, calendar: calendar),
            profile: nil, calendar: calendar, now: now
        )
        #expect(WatchConditioningMapper.program(from: withoutProfile).matIntensityZones == nil)
    }

    // MARK: - Ingest

    private func makeIngestor() -> (WatchConditioningIngestor, SwiftDataMatSessionRepository, ModelContainer) {
        let container = InMemoryModelContainer.make()
        let matSessions = SwiftDataMatSessionRepository(modelContext: container.mainContext)
        let ingestor = WatchConditioningIngestor(
            records: SwiftDataConditioningRecordRepository(modelContext: container.mainContext),
            matSessions: matSessions,
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        return (ingestor, matSessions, container)
    }

    private func delivery(isSavedToHealth: Bool = true) -> WatchCompletedMatSession {
        WatchCompletedMatSession(
            id: UUID(), startTime: start, endTime: start.addingTimeInterval(3_600),
            sport: "muayThai", intensity: "hardSparring", isSavedToHealth: isSavedToHealth
        )
    }

    private func allMatSessions(_ container: ModelContainer) throws -> [MatSession] {
        try container.mainContext.fetch(FetchDescriptor<MatSession>())
    }

    @Test("A watch mat session becomes one MatSession with the watch's values")
    func mapping() throws {
        let (ingestor, matSessions, container) = makeIngestor()
        let saved = delivery()
        let unsaved = delivery(isSavedToHealth: false)
        #expect(ingestor.ingest(saved) == .inserted)
        #expect(ingestor.ingest(unsaved) == .inserted)

        let session = try #require(matSessions.find(id: saved.id))
        #expect(session.sport == .muayThai)
        #expect(session.intensity == .hardSparring)
        #expect(session.startTime == saved.startTime)
        #expect(session.duration == 3_600)
        #expect(session.healthKitWorkoutId == saved.id)
        #expect(try #require(matSessions.find(id: unsaved.id)).healthKitWorkoutId == nil)
        // Never a conditioning record: the program cannot count it.
        #expect(try container.mainContext.fetch(FetchDescriptor<ConditioningRecord>()).isEmpty)
    }

    @Test("Duplicate deliveries produce one session; a redelivery after delete does not resurrect it")
    func idempotent() throws {
        let (ingestor, matSessions, container) = makeIngestor()
        let session = delivery()
        #expect(ingestor.ingest(session) == .inserted)
        #expect(ingestor.ingest(session) == .duplicate)
        #expect(try allMatSessions(container).count == 1)

        matSessions.delete(try #require(matSessions.find(id: session.id)))
        try matSessions.save()
        #expect(ingestor.ingest(session) == .duplicate)
        #expect(try allMatSessions(container).isEmpty)
    }

    @Test("A session already present (e.g. via iCloud) is acknowledged, not duplicated")
    func existingIsDuplicate() throws {
        let (ingestor, matSessions, container) = makeIngestor()
        let session = delivery()
        matSessions.insert(WatchConditioningMapper.matSession(from: session))
        try matSessions.save()
        #expect(ingestor.ingest(session) == .duplicate)
        #expect(try allMatSessions(container).count == 1)
    }
}
