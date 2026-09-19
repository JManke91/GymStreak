import Foundation
@testable import GymStreak

@MainActor
final class RecordingConditioningCues: ConditioningCueDelivering {
    private(set) var played: [ConditioningLiveCue] = []
    private(set) var scheduledBatches: [[ConditioningScheduledCue]] = []
    private(set) var cancelCount = 0
    var isNotificationAllowed = true

    func play(_ cue: ConditioningLiveCue) { played.append(cue) }

    func scheduleBackgroundCues(_ cues: [ConditioningScheduledCue]) async -> Bool {
        scheduledBatches.append(cues)
        return isNotificationAllowed
    }

    func cancelBackgroundCues() { cancelCount += 1 }
}

@MainActor
final class RecordingConditioningWorkoutSaver: ConditioningWorkoutSaving {
    struct Saved: Equatable {
        let externalUUID: UUID
        let modality: ConditioningModality
        let startDate: Date
        let endDate: Date
        let title: String
    }

    var isHealthKitAvailable = true
    /// Set to make the Health write fail, so a test can assert the History record survives it.
    var saveError: (any Error)?
    private(set) var saved: [Saved] = []

    func prepareConditioningAuthorization() async {}

    func saveConditioningWorkout(
        externalUUID: UUID,
        modality: ConditioningModality,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws {
        if let saveError { throw saveError }
        saved.append(Saved(
            externalUUID: externalUUID,
            modality: modality,
            startDate: startDate,
            endDate: endDate,
            title: title
        ))
    }
}

/// In-memory stand-in for the conditioning history repository.
@MainActor
final class RecordingConditioningRecordRepository: ConditioningRecordRepository {
    private(set) var records: [ConditioningRecord] = []
    private(set) var saveCount = 0

    func fetchAll() -> [ConditioningRecord] {
        records.sorted { $0.startTime > $1.startTime }
    }

    func find(id: UUID) -> ConditioningRecord? {
        records.first { $0.id == id }
    }

    func insert(_ record: ConditioningRecord) {
        records.append(record)
    }

    func delete(_ record: ConditioningRecord) {
        records.removeAll { $0.id == record.id }
    }

    func save() throws {
        saveCount += 1
    }
}

@MainActor
final class StubHealthSyncPreference: HealthSyncPreferenceReading {
    var isHealthSyncEnabled = true
}
