//
//  MatSessionLogViewModel.swift
//  GymStreak
//
//  The "Log a mat session" form: sport, start, duration, intensity, note.
//  Saves to History first and to Apple Health second — the session is kept
//  even when the Health write is off or fails. See docs/fight-conditioning.md.
//

import Foundation
import Observation

@Observable
@MainActor
final class MatSessionLogViewModel: Identifiable {

    static let durationRange = 5...300
    static let durationStep = 5

    var sport: MatSport = .bjj
    var intensity: MatIntensity = .moderate
    var durationMinutes = 60
    var note = ""
    /// `nil` until the user picks a start; until then the start follows the
    /// duration ("it just ended"), which is the common case of logging right after training.
    var editedStartDate: Date?

    /// The moment the form opened — the default end of the session.
    @ObservationIgnored let openedAt: Date
    @ObservationIgnored private let sessions: any MatSessionRepository
    @ObservationIgnored private let workoutSaver: any MatSessionWorkoutSaving
    @ObservationIgnored private let healthSync: any HealthSyncPreferenceReading

    init(
        sessions: any MatSessionRepository,
        workoutSaver: any MatSessionWorkoutSaving,
        healthSync: any HealthSyncPreferenceReading,
        now: Date = Date()
    ) {
        self.sessions = sessions
        self.workoutSaver = workoutSaver
        self.healthSync = healthSync
        self.openedAt = now
    }

    var startDate: Date {
        editedStartDate ?? openedAt.addingTimeInterval(-duration)
    }

    private var duration: TimeInterval { TimeInterval(durationMinutes * 60) }

    /// Writes the session to History, then — when Health sync is on — to Apple Health.
    ///
    /// The record is created first and never depends on the Health write: GymStreak is the
    /// source of truth, exactly as for conditioning records. Returns the saved session's id,
    /// `nil` if the local save failed.
    @discardableResult
    func save() async -> UUID? {
        let start = startDate
        let end = start.addingTimeInterval(duration)
        let session = MatSession(
            startTime: start,
            endTime: end,
            sport: sport,
            intensity: intensity,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        sessions.insert(session)
        do {
            try sessions.save()
        } catch {
            print("Mat session save failed: \(error)")
            return nil
        }
        NotificationCenter.default.post(name: .historySourceDataDidChange, object: nil)

        let id = session.id
        guard healthSync.isHealthSyncEnabled, workoutSaver.isHealthKitAvailable else { return id }
        await workoutSaver.prepareConditioningAuthorization()
        do {
            try await workoutSaver.saveMatSessionWorkout(
                externalUUID: id,
                sport: sport,
                startDate: start,
                endDate: end,
                title: MatSessionCopy.sport(sport)
            )
            // Re-resolved rather than captured: the user may have deleted it meanwhile.
            sessions.find(id: id)?.healthKitWorkoutId = id
            try? sessions.save()
        } catch {
            print("Mat session Health save failed: \(error)")
        }
        return id
    }
}
