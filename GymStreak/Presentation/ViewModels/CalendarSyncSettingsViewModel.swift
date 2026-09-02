//
//  CalendarSyncSettingsViewModel.swift
//  GymStreak
//
//  Drives the "Sync to Apple Calendar" toggle: the permission handshake, the
//  calendar's creation and removal, and what the user is told when it fails.
//  See docs/calendar-sync.md.
//

import Foundation
import Observation

/// The Settings toggle's state machine.
///
/// Keeps the intent flag and the system's actual permission from drifting in
/// the one direction that matters here: the flag is only ever written to `true`
/// *after* access is granted and the calendar exists, so a denied prompt leaves
/// the toggle off rather than lying about it.
@Observable
@MainActor
final class CalendarSyncSettingsViewModel {

    /// What to tell the user when the toggle could not do what they asked.
    enum Failure: Equatable {
        /// Refused, "Add Only", or restricted — the copy names the Settings path.
        case accessDenied
        /// No iCloud and no local account to own a calendar on.
        case noWritableSource
        /// EventKit refused the save or the delete.
        case writeFailed
    }

    private let preference: any CalendarSyncPreferenceProviding
    private let sync: any WorkoutCalendarSyncing

    /// The value the toggle should show while the request is in flight, so the
    /// switch follows the user's finger instead of snapping back and forth.
    /// Cleared once the outcome is known.
    private var pendingValue: Bool?

    private(set) var isWorking = false
    private(set) var failure: Failure?

    init(
        preference: any CalendarSyncPreferenceProviding,
        sync: any WorkoutCalendarSyncing
    ) {
        self.preference = preference
        self.sync = sync
    }

    /// What the toggle renders.
    var isEnabled: Bool {
        pendingValue ?? preference.isCalendarSyncEnabled
    }

    /// Handles a flip of the toggle.
    ///
    /// Turning on asks for access and creates the calendar; only if both
    /// succeed is the flag persisted. Turning off persists immediately — the
    /// user's intent stands even if removing the calendar then fails — and
    /// reports the removal failure rather than silently swallowing it.
    func setEnabled(_ isOn: Bool) async {
        guard !isWorking else { return }
        failure = nil
        pendingValue = isOn
        isWorking = true
        defer {
            isWorking = false
            pendingValue = nil
        }

        if isOn {
            do {
                try await sync.enable()
                preference.isCalendarSyncEnabled = true
            } catch {
                preference.isCalendarSyncEnabled = false
                failure = Self.failure(for: error)
            }
        } else {
            preference.isCalendarSyncEnabled = false
            do {
                try sync.disable()
            } catch {
                failure = Self.failure(for: error)
            }
        }
    }

    private static func failure(for error: any Error) -> Failure {
        switch error as? WorkoutCalendarSyncError {
        case .accessDenied: .accessDenied
        case .noWritableSource: .noWritableSource
        default: .writeFailed
        }
    }
}
