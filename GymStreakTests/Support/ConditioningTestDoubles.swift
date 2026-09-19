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
        let modality: ConditioningModality
        let startDate: Date
        let endDate: Date
        let title: String
    }

    var isHealthKitAvailable = true
    private(set) var saved: [Saved] = []

    func prepareConditioningAuthorization() async {}

    func saveConditioningWorkout(
        modality: ConditioningModality,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws -> UUID {
        saved.append(Saved(modality: modality, startDate: startDate, endDate: endDate, title: title))
        return UUID()
    }
}

@MainActor
final class StubHealthSyncPreference: HealthSyncPreferenceReading {
    var isHealthSyncEnabled = true
}
