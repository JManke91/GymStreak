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
    ///
    /// - Parameter revalidatingCalendar: whether the pass must reach the
    ///   calendar even when the app's desired state has not moved since the last
    ///   one.
    ///
    ///   The plumbing triggers (a plan edit, a completion, a routines refresh)
    ///   pass `false` and are short-circuited when nothing changed, because they
    ///   fire often and a pass ends in a query against a CalDAV-backed store.
    ///   But the two ways this feature can be *taken away* — the user deleting
    ///   the app's calendar in Calendar.app, or revoking Calendar access in
    ///   Settings — change nothing about the app's desired state, and iOS
    ///   announces neither. They are only ever discovered by actually trying, so
    ///   the once-per-activation trigger passes `true` and accepts one query for
    ///   it (docs/calendar-sync.md §12).
    func reconcile(revalidatingCalendar: Bool)
}

extension PlannedWorkoutCalendarMirroring {

    /// The ordinary pass: something the app knows about changed.
    func reconcile() {
        reconcile(revalidatingCalendar: false)
    }
}
