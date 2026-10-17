import Foundation
@testable import GymStreak

/// Records Apple Health writes for logged mat sessions (docs/fight-conditioning.md).
@MainActor
final class RecordingMatSessionWorkoutSaver: MatSessionWorkoutSaving {
    struct Saved: Equatable {
        let externalUUID: UUID
        let sport: MatSport
        let startDate: Date
        let endDate: Date
    }

    var isHealthKitAvailable = true
    var saveError: (any Error)?
    private(set) var saved: [Saved] = []

    func prepareConditioningAuthorization() async {}

    func saveMatSessionWorkout(
        externalUUID: UUID,
        sport: MatSport,
        startDate: Date,
        endDate: Date,
        title: String
    ) async throws {
        if let saveError { throw saveError }
        saved.append(Saved(externalUUID: externalUUID, sport: sport, startDate: startDate, endDate: endDate))
    }
}
