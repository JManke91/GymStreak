//
//  CalendarSyncOptInTests.swift
//  GymStreakTests
//
//  The opt-in seam of calendar sync (docs/calendar-sync.md). Two things are
//  load-bearing here: the flag survives a relaunch, and it is only ever
//  written `true` after the calendar actually exists — a denied prompt must
//  leave the toggle off rather than claim a sync that cannot happen.
//
//  The real `EKEventStore` is never exercised; `FakeWorkoutCalendarSync` is
//  what the protocol seam exists for.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct CalendarSyncOptInTests {

    /// A defaults suite of its own per test, so nothing writes into the
    /// device's real `UserDefaults` and no test can see another's flag.
    private static func throwawayDefaults(
        _ name: String = #function
    ) -> UserDefaults {
        let suiteName = "test.calendar_sync.\(name).\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - The enable flag

    @Test("Calendar sync is off on a fresh install")
    func offByDefault() {
        let preference = CalendarSyncPreference(defaults: Self.throwawayDefaults())
        #expect(preference.isCalendarSyncEnabled == false)
    }

    @Test("The flag is written through, so it survives relaunch")
    func flagSurvivesRelaunch() {
        let defaults = Self.throwawayDefaults()

        let first = CalendarSyncPreference(defaults: defaults)
        first.isCalendarSyncEnabled = true

        // A second instance over the same suite is what a relaunch looks like.
        let afterRelaunch = CalendarSyncPreference(defaults: defaults)
        #expect(afterRelaunch.isCalendarSyncEnabled == true)
    }

    @Test("Switching back off is written through too")
    func flagClearsOnDisable() {
        let defaults = Self.throwawayDefaults()

        let first = CalendarSyncPreference(defaults: defaults)
        first.isCalendarSyncEnabled = true
        first.isCalendarSyncEnabled = false

        #expect(CalendarSyncPreference(defaults: defaults).isCalendarSyncEnabled == false)
    }

    // MARK: - Enabling

    @Test("Granting access persists the flag and leaves the app owning a calendar")
    func enableOnGrant() async {
        let (viewModel, preference, sync) = makeSubject()

        await viewModel.setEnabled(true)

        #expect(preference.isCalendarSyncEnabled == true)
        #expect(viewModel.isEnabled == true)
        #expect(viewModel.failure == nil)
        #expect(sync.appCalendarIdentifier != nil)
    }

    @Test("A second enable does not create a second calendar")
    func enableIsIdempotent() async {
        let (viewModel, _, sync) = makeSubject()

        await viewModel.setEnabled(true)
        let firstIdentifier = sync.appCalendarIdentifier
        await viewModel.setEnabled(true)

        #expect(sync.appCalendarIdentifier == firstIdentifier)
    }

    // MARK: - Denied and restricted

    @Test("A denied prompt leaves the toggle off and names the remedy")
    func deniedLeavesToggleOff() async {
        let (viewModel, preference, sync) = makeSubject()
        sync.enableError = WorkoutCalendarSyncError.accessDenied

        await viewModel.setEnabled(true)

        #expect(preference.isCalendarSyncEnabled == false)
        // `isEnabled` is what the switch renders — it must not be left showing
        // the value the user tapped for.
        #expect(viewModel.isEnabled == false)
        #expect(viewModel.failure == .accessDenied)
        #expect(sync.appCalendarIdentifier == nil)
    }

    @Test("Restricted access is reported the same way, and asking again does not loop")
    func restrictedDoesNotLoopThePrompt() async {
        let (viewModel, preference, sync) = makeSubject()
        // Restricted by a profile: the gateway maps it to the same refusal,
        // because the user cannot grant it either way.
        sync.accessStatus = .restricted
        sync.enableError = WorkoutCalendarSyncError.accessDenied

        await viewModel.setEnabled(true)
        await viewModel.setEnabled(true)

        // Each tap asks exactly once — the view model never retries on its own,
        // and the system answers a decided permission without presenting a
        // second prompt.
        #expect(sync.enableCallCount == 2)
        #expect(preference.isCalendarSyncEnabled == false)
        #expect(viewModel.failure == .accessDenied)
    }

    @Test("No writable account is a distinct failure, not a permission problem")
    func noWritableSourceIsItsOwnFailure() async {
        let (viewModel, preference, sync) = makeSubject()
        sync.enableError = WorkoutCalendarSyncError.noWritableSource

        await viewModel.setEnabled(true)

        #expect(preference.isCalendarSyncEnabled == false)
        #expect(viewModel.failure == .noWritableSource)
    }

    @Test("An EventKit write failure is reported as a retryable failure")
    func writeFailureIsReported() async {
        let (viewModel, preference, sync) = makeSubject()
        sync.enableError = WorkoutCalendarSyncError.calendarWriteFailed("nope")

        await viewModel.setEnabled(true)

        #expect(preference.isCalendarSyncEnabled == false)
        #expect(viewModel.failure == .writeFailed)
    }

    // MARK: - Disabling

    @Test("Disabling removes the app's calendar and clears the flag")
    func disableRemovesCalendar() async {
        let (viewModel, preference, sync) = makeSubject()
        await viewModel.setEnabled(true)

        await viewModel.setEnabled(false)

        #expect(preference.isCalendarSyncEnabled == false)
        #expect(sync.appCalendarIdentifier == nil)
        #expect(sync.disableCallCount == 1)
        #expect(viewModel.failure == nil)
    }

    @Test("A failed removal still honours the user's intent to switch off")
    func disableFailureKeepsTheToggleOff() async {
        let (viewModel, preference, sync) = makeSubject()
        await viewModel.setEnabled(true)
        sync.disableError = WorkoutCalendarSyncError.calendarWriteFailed("nope")

        await viewModel.setEnabled(false)

        // The user asked for off; flipping it back on because a delete failed
        // would be the app arguing with them. The failure is surfaced instead.
        #expect(preference.isCalendarSyncEnabled == false)
        #expect(viewModel.failure == .writeFailed)
    }

    // MARK: - The orphaned-calendar regression (found on device, 2026-09-02)

    @Test("Switching off without access keeps the app's handle on its calendar")
    func disableWithoutAccessKeepsTheIdentifier() async {
        let (viewModel, preference, sync) = makeSubject()
        await viewModel.setEnabled(true)
        let identifier = sync.appCalendarIdentifier
        #expect(identifier != nil)

        // The user revoked access, or downgraded it to "Add Only", in Settings.
        sync.accessStatus = .denied

        await viewModel.setEnabled(false)

        // The calendar is still in Calendar.app, so the app must keep claiming
        // it. Dropping the handle here is what left three "Gym Streak"
        // calendars on the test device: each later enable built a new one.
        #expect(sync.appCalendarIdentifier == identifier)
        #expect(preference.isCalendarSyncEnabled == false)
        #expect(viewModel.failure == .accessDenied)
    }

    @Test("Restoring access and re-enabling adopts the same calendar, not a second one")
    func reEnableAfterRevokeDoesNotDuplicate() async {
        let (viewModel, _, sync) = makeSubject()
        await viewModel.setEnabled(true)
        let identifier = sync.appCalendarIdentifier

        // Revoke → switch off (which cannot remove it) → grant again → switch on.
        sync.accessStatus = .denied
        await viewModel.setEnabled(false)
        await viewModel.setEnabled(true)

        #expect(sync.appCalendarIdentifier == identifier)
    }

    @Test("A new failure clears the previous one")
    func failureIsClearedOnRetry() async {
        let (viewModel, _, sync) = makeSubject()
        sync.enableError = WorkoutCalendarSyncError.accessDenied
        await viewModel.setEnabled(true)
        #expect(viewModel.failure == .accessDenied)

        sync.enableError = nil
        await viewModel.setEnabled(true)

        #expect(viewModel.failure == nil)
    }

    // MARK: - Helpers

    private func makeSubject(
        _ name: String = #function
    ) -> (CalendarSyncSettingsViewModel, CalendarSyncPreference, FakeWorkoutCalendarSync) {
        let preference = CalendarSyncPreference(defaults: Self.throwawayDefaults(name))
        let sync = FakeWorkoutCalendarSync()
        let viewModel = CalendarSyncSettingsViewModel(preference: preference, sync: sync)
        return (viewModel, preference, sync)
    }
}
