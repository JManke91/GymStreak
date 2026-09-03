//
//  PlannedWorkoutCalendarReconciler.swift
//  GymStreak
//
//  The policy half of calendar sync: given the state the app wants the user's
//  calendar to be in and the markers already in it, decide what to create and
//  what to delete. Pure Foundation — no EventKit, no ViewModel, no entitlement —
//  so the interesting logic is unit-testable while the real `EKEventStore` stays
//  out of the test suite entirely.
//  See docs/calendar-sync.md.
//

import Foundation

// MARK: - Window

/// The stretch of calendar the mirror is responsible for on one pass, in whole
/// days, both ends inclusive.
///
/// It carries its own **widened query range** because
/// `predicateForEvents(withStart:end:calendars:)` is an *overlap* query whose
/// boundary inclusivity Apple does not document (it does document that the range
/// is evaluated in the default time zone). Asking for a day more on each side and
/// then filtering precisely with `contains(day:)` removes the dependency on the
/// undocumented edge at no cost — an event a day outside the window must not be
/// diffed, because "not wanted" means "delete".
struct MirrorWindow: Equatable, Sendable {
    /// First day the mirror owns — today. Everything before it is left alone.
    let firstDay: Date
    /// Last day the mirror owns, inclusive.
    let lastDay: Date
    /// Start of the range handed to EventKit — one day before `firstDay`.
    let queryStart: Date
    /// Exclusive end of the range handed to EventKit — two days past `lastDay`.
    let queryEnd: Date

    /// The widened query bounds are derived once here rather than on each read,
    /// so nothing builds a `Calendar` inside the per-event filter loop.
    init(firstDay: Date, lastDay: Date, calendar: Calendar) {
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.queryStart = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        self.queryEnd = calendar.date(byAdding: .day, value: 2, to: lastDay) ?? lastDay
    }

    /// Whether a day the calendar came back with is one this pass may act on.
    ///
    /// Takes a **start-of-day** date: the caller already holds the `Calendar` it
    /// normalized every event's `startDate` with, and re-deriving one per event
    /// here would put that construction in a loop for no gain.
    func covers(startOfDay day: Date) -> Bool {
        day >= firstDay && day <= lastDay
    }
}

// MARK: - Reconciler

enum PlannedWorkoutCalendarReconciler {

    /// How far ahead the calendar is read back, at minimum, when looking for
    /// events the app wrote earlier.
    ///
    /// It has to outlive the plans it is cleaning up after: the planning sheet
    /// caps the cadence at 30 days and the mirror writes 8 occurrences per
    /// routine, so a plan anchored today reaches ~240 days out. 400 leaves room
    /// for a reference date set a few months ahead, so shortening or clearing a
    /// long cadence still finds the events it left behind.
    ///
    /// A weekday series needs none of this reach — it repeats weekly, so its
    /// next occurrence is always within seven days — and reading it back through
    /// this window is **not** free: `events(matching:)` expands a recurrence, so
    /// one series materializes ~170 `EKEvent`s per pass on the main actor
    /// (docs/calendar-sync.md §13e). Measured at 40 cadence routines and found
    /// imperceptible (§12g), but that measurement predates the expansion; a
    /// shorter second read for series, or the `actor` escalation in §5, is the
    /// route if it ever bites.
    static let minimumWindowDays = 400

    /// The span of calendar the mirror owns on this pass.
    ///
    /// **It starts today, so the past is never touched.** Events for days that
    /// have already passed are a record of what the user planned, and deleting
    /// them would quietly rewrite their calendar history every time a plan
    /// changed.
    static func mirrorWindow(
        desired: PlannedWorkoutCalendarState,
        referenceDate: Date = Date()
    ) -> MirrorWindow {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let firstDay = calendar.startOfDay(for: referenceDate)
        let floor = calendar.date(byAdding: .day, value: minimumWindowDays, to: firstDay) ?? firstDay
        let furthest = desired.occurrences.map({ calendar.startOfDay(for: $0.day) }).max() ?? firstDay
        return MirrorWindow(firstDay: firstDay, lastDay: max(floor, furthest), calendar: calendar)
    }

    /// The create/delete plan that turns `existing` into `desired`.
    ///
    /// Idempotent by construction: an unchanged plan matches every marker and
    /// yields no actions at all, so a repeat pass costs the user's calendar
    /// nothing — no churn, no CalDAV round-trips. That holds for a weekday series
    /// too, whose match is on the *pattern* rather than on the start date: an
    /// open-ended weekly rule produces the same upcoming days no matter which
    /// past week it started in, so a series is left alone until the selected
    /// weekdays themselves change.
    ///
    /// Deletes come first so a shortened cadence — or a routine leaving the
    /// weekday shape — frees its old days before the new ones are written.
    static func actions(
        desired: PlannedWorkoutCalendarState,
        existing: [MirroredWorkoutEvent]
    ) -> [WorkoutCalendarMirrorAction] {
        // Deduplicate the desired side too: two occurrence markers can only
        // collide when a routine is planned twice for the same day, and two
        // series markers only when one routine appears twice. The calendar shows
        // one event either way.
        var wantedOccurrences: [String: PlannedWorkoutOccurrence] = [:]
        var occurrenceOrder: [String] = []
        for occurrence in desired.occurrences where wantedOccurrences[occurrence.marker] == nil {
            wantedOccurrences[occurrence.marker] = occurrence
            occurrenceOrder.append(occurrence.marker)
        }
        var wantedSeries: [String: PlannedWorkoutSeries] = [:]
        var seriesOrder: [String] = []
        for series in desired.series where wantedSeries[series.marker] == nil {
            wantedSeries[series.marker] = series
            seriesOrder.append(series.marker)
        }

        var matched: Set<String> = []
        var deletes: [WorkoutCalendarMirrorAction] = []
        for event in existing {
            guard let identity = event.markerURL.flatMap(PlannedWorkoutMarker.identity) else {
                // Not ours: an event the user added to the app's calendar
                // themselves. Left exactly where it is.
                continue
            }
            switch identity {
            case .occurrence(let marker):
                if wantedOccurrences[marker] != nil, !matched.contains(marker) {
                    matched.insert(marker)
                } else {
                    // Either the plan no longer wants this day, or it is a
                    // duplicate of one already kept.
                    deletes.append(.delete(reference: event.reference))
                }
            case .series(let marker):
                // A series only survives when the pattern in the calendar is
                // still the pattern the plan asks for. Anything else — a changed
                // weekday set, a routine that left the weekday shape, a duplicate
                // — is removed and, where still wanted, written fresh below.
                // `EKRecurrenceRule` is immutable, so there is no third option
                // (docs/calendar-sync.md §13d).
                if let wanted = wantedSeries[marker],
                   event.recurringWeekdays == wanted.weekdays,
                   !matched.contains(marker) {
                    matched.insert(marker)
                } else {
                    deletes.append(.deleteSeries(reference: event.reference))
                }
            }
        }

        let creates = occurrenceOrder
            .filter { !matched.contains($0) }
            .compactMap { wantedOccurrences[$0] }
            .map { WorkoutCalendarMirrorAction.create($0) }
        let seriesCreates = seriesOrder
            .filter { !matched.contains($0) }
            .compactMap { wantedSeries[$0] }
            .map { WorkoutCalendarMirrorAction.createSeries($0) }

        return deletes + creates + seriesCreates
    }
}
