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
    var appCalendarIdentifier: String?

    /// Thrown by `enable()` instead of creating a calendar, when set.
    var enableError: (any Error)?
    /// Thrown by `disable()` instead of removing the calendar, when set.
    var disableError: (any Error)?

    /// Thrown by `mirror(_:)` instead of recording, when set.
    var mirrorError: (any Error)?

    /// The user deleted the app's calendar in Calendar.app: the app still holds
    /// an identifier, but it no longer resolves. Modelled here rather than by
    /// clearing `appCalendarIdentifier`, because the whole point of the case is
    /// that the app does not know until it tries.
    var isCalendarMissing = false

    private(set) var enableCallCount = 0
    private(set) var disableCallCount = 0
    /// Every desired state handed to `mirror`, in order.
    private(set) var mirroredStates: [PlannedWorkoutCalendarState] = []

    /// The cadence half of each recorded pass — what most assertions look at.
    var mirroredOccurrences: [[PlannedWorkoutOccurrence]] { mirroredStates.map(\.occurrences) }
    /// The weekday half of each recorded pass.
    var mirroredSeries: [[PlannedWorkoutSeries]] { mirroredStates.map(\.series) }

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

    func mirror(_ desired: PlannedWorkoutCalendarState) throws {
        if let mirrorError {
            throw mirrorError
        }
        // The real gateway's own guards, in the same order — access first, then
        // the calendar. A fake that recorded regardless would let the mirror's
        // handling of both take-it-away cases pass untested.
        guard accessStatus == .fullAccess else {
            throw WorkoutCalendarSyncError.accessDenied
        }
        guard appCalendarIdentifier != nil else { return }
        guard !isCalendarMissing else {
            throw WorkoutCalendarSyncError.calendarMissing
        }
        mirroredStates.append(desired)
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
        isCalendarMissing = false
    }
}
