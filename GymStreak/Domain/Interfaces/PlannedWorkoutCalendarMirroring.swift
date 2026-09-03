//
//  PlannedWorkoutCalendarMirroring.swift
//  GymStreak
//
//  The one call every trigger site makes when a plan changes: "bring the
//  calendar in line". Keeps the ViewModels free of repositories-plus-gateway
//  glue and gives tests a seam to record against.
//  See docs/calendar-sync.md.
//

import Foundation

/// Brings the app-owned calendar in line with the user's current plans.
///
/// `@MainActor` because the gateway underneath confines a non-`Sendable`
/// `EKEventStore` (rule 2 of docs/swift6-concurrency.md).
@MainActor
protocol PlannedWorkoutCalendarMirroring: AnyObject {

    /// Mirrors every active plan, or does nothing when the user has not switched
    /// calendar sync on.
    ///
    /// **Never throws.** The plan is the source of truth and the calendar is a
    /// projection of it: a calendar write that fails must leave the user's
    /// schedule change saved and surface nothing intrusive, so failures are
    /// logged and swallowed here rather than travelling back to a call site that
    /// has already committed.
    func reconcile()
}
