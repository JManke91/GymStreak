//
//  CalendarSyncPreferenceProviding.swift
//  GymStreak
//
//  Protocol surface for the "Sync to Apple Calendar" opt-in, so Presentation
//  depends on an abstraction rather than the `CalendarSyncPreference`
//  singleton. Sibling of `WeightUnitPreferenceProviding`.
//

import Foundation

/// Whether the user has switched calendar sync on.
///
/// This is the *intent* flag only — it says nothing about whether Calendar
/// access is still granted or whether the app-owned calendar still exists.
/// Those live behind `WorkoutCalendarSyncing`.
///
/// `@MainActor` for the same reason as `WeightUnitPreferenceProviding`: the
/// only conformer is main-actor-isolated mutable state bound straight into
/// SwiftUI.
@MainActor
protocol CalendarSyncPreferenceProviding: AnyObject {

    /// `false` until the user turns the toggle on and access is granted.
    var isCalendarSyncEnabled: Bool { get set }
}
