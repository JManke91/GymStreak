//
//  ConditioningShareViewModelTests.swift
//  GymStreakTests
//
//  `ConditioningShareViewModel`: heart rate is read only for a session that reached Apple
//  Health, and the card falls back to the no-heart-rate state. See docs/workout-sharing.md.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ConditioningShareViewModelTests {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func makeRecord(inHealth: Bool) -> ConditioningRecord {
        let id = UUID()
        return ConditioningRecord(
            id: id, startTime: start, endTime: start.addingTimeInterval(60),
            sessionTypeRaw: "", titleSnapshot: "Intervals", energySystemRaw: "",
            modalityRaw: ConditioningModality.rower.rawValue, effortRaw: ConditioningEffort.maximal.rawValue,
            roundsCompleted: 3, roundsPlanned: 3, setsPlanned: 0, workInterval: 10, restInterval: 15,
            endedEarly: false, healthKitWorkoutId: inHealth ? id : nil
        )
    }

    private func makeViewModel(
        records: RecordingConditioningRecordRepository,
        heartRates: StubHeartRateReader,
        profile: HeartRateProfile? = HeartRateProfile(maxSource: .measured, measuredMaxHeartRate: 200)
    ) -> ConditioningShareViewModel {
        ConditioningShareViewModel(
            records: records,
            heartRates: heartRates,
            heartRateProfiles: StubHeartRateProfileStore(profile: profile),
            photoLibrary: NoopPhotoLibrary(),
            campaign: "test"
        )
    }

    private var fullMinute: [HeartRateReading] {
        (0..<12).map {
            let date = start.addingTimeInterval(Double($0) * 5)
            return HeartRateReading(start: date, end: date, bpm: 170)
        }
    }

    @Test
    func sessionInHealthGetsHeartRateAndZones() async {
        let records = RecordingConditioningRecordRepository()
        let record = makeRecord(inHealth: true)
        records.insert(record)
        let heartRates = StubHeartRateReader(readings: fullMinute)
        let viewModel = makeViewModel(records: records, heartRates: heartRates)

        #expect(await viewModel.prepare(recordID: record.id))
        #expect(heartRates.callCount == 1)
        #expect(viewModel.card?.isHeartRateChipShown == true)
        #expect(viewModel.card?.zones.first { $0.id == 3 }?.fraction == 1) // 170 bpm is Z4 of 200
    }

    @Test
    func sessionNotInHealthIsNeverLookedUp() async {
        let records = RecordingConditioningRecordRepository()
        let record = makeRecord(inHealth: false)
        records.insert(record)
        let heartRates = StubHeartRateReader(readings: fullMinute)
        let viewModel = makeViewModel(records: records, heartRates: heartRates)

        #expect(await viewModel.prepare(recordID: record.id))
        #expect(heartRates.callCount == 0)
        #expect(viewModel.card?.isHeartRateChipShown == false)
        #expect(viewModel.card?.zones.isEmpty == true)
    }

    @Test
    func unknownRecordPreparesNothing() async {
        let viewModel = makeViewModel(records: RecordingConditioningRecordRepository(), heartRates: StubHeartRateReader(readings: []))
        #expect(await viewModel.prepare(recordID: UUID()) == false)
        #expect(viewModel.card == nil)
    }
}

@MainActor
private final class StubHeartRateReader: ConditioningHeartRateReading {
    let readings: [HeartRateReading]
    private(set) var callCount = 0

    init(readings: [HeartRateReading]) {
        self.readings = readings
    }

    func readings(from start: Date, to end: Date) async -> [HeartRateReading] {
        callCount += 1
        return readings
    }
}

@MainActor
private final class StubHeartRateProfileStore: HeartRateProfileStoring {
    var heartRateProfile: HeartRateProfile?
    var onChange: (() -> Void)?

    init(profile: HeartRateProfile?) {
        heartRateProfile = profile
    }
}

private struct NoopPhotoLibrary: PhotoLibrarySaving {
    func savePNG(_ data: Data) async throws {}
}
