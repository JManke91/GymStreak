//
//  FakeWorkoutCalendarSync.swift
//  GymStreakTests
//
//  Stands in for `EventKitWorkoutCalendarSync` so the toggle's state machine
//  can be exercised without EventKit — the real `EKEventStore` is never touched
//  in unit tests, mirroring `MockHealthKitWorkoutServicing`.
//

import Foundation
@testable import GymStreak

@MainActor
final class FakeWorkoutCalendarSync: WorkoutCalendarSyncing {

    var accessStatus: CalendarAccessStatus = .notDetermined
    private(set) var appCalendarIdentifier: String?

    /// Thrown by `enable()` instead of creating a calendar, when set.
    var enableError: (any Error)?
    /// Thrown by `disable()` instead of removing the calendar, when set.
    var disableError: (any Error)?

    private(set) var enableCallCount = 0
    private(set) var disableCallCount = 0

    func enable() async throws {
        enableCallCount += 1
        if let enableError {
            throw enableError
        }
        accessStatus = .fullAccess
        // Idempotent, like the real one: a second enable reuses the calendar
        // it already owns instead of creating a second.
        if appCalendarIdentifier == nil {
            appCalendarIdentifier = UUID().uuidString
        }
    }

    func disable() throws {
        disableCallCount += 1
        if let disableError {
            throw disableError
        }
        // Mirrors the real gateway: without full access the calendar cannot be
        // removed, so the handle on it is **kept** rather than dropped. Letting
        // the fake clear it here would hide the orphaned-calendar bug that
        // device testing found (see docs/calendar-sync.md §4).
        guard accessStatus == .fullAccess else {
            throw WorkoutCalendarSyncError.accessDenied
        }
        appCalendarIdentifier = nil
    }
}
