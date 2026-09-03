//
//  PlannedWorkoutCalendarState.swift
//  GymStreak
//
//  The vocabulary the calendar mirror reasons in: what the app wants the user's
//  calendar to show, what it found there, and what to do about the difference.
//  Pure Foundation — no EventKit — so the reconciler that consumes these stays
//  unit-testable without an `EKEventStore`.
//  See docs/calendar-sync.md §13.
//

import Foundation

// MARK: - Desired state

/// One planned session the app-owned calendar should show, as an all-day event.
///
/// The shape a **cadence** plan takes: a rolling window of one-shot events,
/// because the whole series re-anchors on the last completed workout and would
/// otherwise have to be destroyed and rebuilt after nearly every session
/// (docs/calendar-sync.md §11a).
struct PlannedWorkoutOccurrence: Equatable, Sendable {
    let routineId: UUID
    /// Start of the day the session is planned for, in the user's calendar.
    let day: Date
    /// What the event is called, already localized ("Push Workout").
    let title: String

    /// The identity written into `EKEvent.url` and read back on the next pass.
    var marker: String {
        PlannedWorkoutMarker.occurrenceString(routineId: routineId, day: day)
    }
}

/// One planned routine that recurs on fixed weekdays, as a single **repeating**
/// all-day event.
///
/// The shape a **weekday** plan takes, and the reason the two shapes differ is
/// the schedule's own semantics rather than a taste for variety: Mon/Wed/Fri is
/// Mon/Wed/Fri whether the user trained late, early or not at all, so it never
/// re-anchors. Expressing it as a recurrence buys the one thing a materialized
/// window cannot — the calendar does not run dry when the app is not opened for
/// months (docs/calendar-sync.md §13a).
struct PlannedWorkoutSeries: Equatable, Sendable {
    let routineId: UUID
    /// Selected ISO weekdays, 1 = Monday … 7 = Sunday — the same numbering
    /// `RoutineSchedule.weekdays` uses, and deliberately *not* EventKit's.
    let weekdays: Set<Int>
    /// Start of the day the series begins on — the first upcoming occurrence.
    let firstDay: Date
    /// What the event is called, already localized ("Push Workout").
    let title: String

    /// One marker for the whole series, with no day in it: Apple documents that
    /// "recurring event identifiers are the same for all occurrences", so the
    /// series — not the occurrence — is the unit that has an identity here.
    var marker: String {
        PlannedWorkoutMarker.seriesString(routineId: routineId)
    }
}

/// Everything the app wants its calendar to hold on this pass, in both shapes.
///
/// One vocabulary rather than two code paths: a routine moving between the
/// cadence and the weekday shape simply contributes to the other list, and the
/// diff removes whatever no longer matches. Nothing at the call site knows a
/// transition happened (docs/calendar-sync.md §13c).
struct PlannedWorkoutCalendarState: Equatable, Sendable {
    var occurrences: [PlannedWorkoutOccurrence] = []
    var series: [PlannedWorkoutSeries] = []

    static let empty = PlannedWorkoutCalendarState()

    var isEmpty: Bool { occurrences.isEmpty && series.isEmpty }
}

// MARK: - Observed state

/// An event already present in the mirrored window, projected off `EKEvent` so
/// this layer never sees EventKit.
struct MirroredWorkoutEvent: Equatable, Sendable {
    /// A positional handle the gateway mints for **this pass only** — the index
    /// of the event in the batch it just read.
    ///
    /// Deliberately *not* `eventIdentifier`: Apple documents that "if an event's
    /// calendar is changed, the eventIdentifier is likely to change as well", so
    /// it is unfit as a durable key and nothing here persists one.
    let reference: Int
    /// `EKEvent.url`, if the event carries one. `nil` — or anything that does
    /// not parse as a marker — means the app did not write this event.
    let markerURL: String?
    /// The ISO weekdays the event actually repeats on, when it carries a weekly
    /// recurrence rule; `nil` for a one-shot event.
    ///
    /// Projected back out of the rule because the series marker carries no
    /// pattern: it is the only way the diff can tell "Mon/Wed/Fri, unchanged"
    /// from "the user just swapped Friday for Saturday".
    let recurringWeekdays: Set<Int>?

    init(reference: Int, markerURL: String?, recurringWeekdays: Set<Int>? = nil) {
        self.reference = reference
        self.markerURL = markerURL
        self.recurringWeekdays = recurringWeekdays
    }
}

// MARK: - Actions

/// What the gateway should do to bring the calendar in line with the plan.
///
/// Deleting a series is its own case rather than a parameter on `delete`,
/// because the two need different `EKSpan`s and the choice is a decision this
/// layer makes, not one the gateway should re-derive.
enum WorkoutCalendarMirrorAction: Equatable, Sendable {
    case create(PlannedWorkoutOccurrence)
    case delete(reference: Int)
    case createSeries(PlannedWorkoutSeries)
    /// Removed with `EKSpan.futureEvents`, so occurrences that have already
    /// passed stay in the user's calendar as the record they are.
    case deleteSeries(reference: Int)
}
