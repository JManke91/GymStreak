//
//  PlannedWorkoutCalendarReconciler.swift
//  GymStreak
//
//  The policy half of calendar sync: given the occurrences the app wants the
//  user's calendar to show and the markers already in it, decide what to create
//  and what to delete. Pure Foundation — no EventKit, no ViewModel, no
//  entitlement — so the interesting logic is unit-testable while the real
//  `EKEventStore` stays out of the test suite entirely.
//  See docs/calendar-sync.md.
//

import Foundation

// MARK: - Values

/// One planned session the app-owned calendar should show, as an all-day event.
struct PlannedWorkoutOccurrence: Equatable, Sendable {
    let routineId: UUID
    /// Start of the day the session is planned for, in the user's calendar.
    let day: Date
    /// What the event is called, already localized ("Push Workout").
    let title: String

    /// The identity written into `EKEvent.url` and read back on the next pass.
    var marker: String {
        PlannedWorkoutMarker.string(routineId: routineId, day: day)
    }
}

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
}

/// What the gateway should do to bring the calendar in line with the plan.
enum WorkoutCalendarMirrorAction: Equatable, Sendable {
    case create(PlannedWorkoutOccurrence)
    case delete(reference: Int)
}

// MARK: - Marker

/// The `gymstreak://routine/<uuid>/occurrence/<yyyy-MM-dd>` stamp that gives
/// every written event its identity.
///
/// **Identity lives in the event, not in local bookkeeping.** Because the app
/// owns its calendar exclusively, reading the marker back out of the calendar is
/// both simpler and more robust than persisting identifiers: there is no local
/// map to drift, and a reinstall — or a second device syncing the same CalDAV
/// calendar — sees exactly the same state. The calendar *is* the state.
///
/// The marker goes in `url` rather than `notes` so the notes field stays the
/// user's own. The app already declares `CFBundleURLTypes` for this scheme.
enum PlannedWorkoutMarker {

    private static let scheme = "gymstreak"
    private static let routineHost = "routine"
    private static let occurrenceSegment = "occurrence"

    /// The marker for a routine's occurrence on a given day.
    ///
    /// The day is rendered from `Calendar` components rather than a
    /// `DateFormatter`: a formatter caches its time zone at construction, and
    /// hoisting one as a `static let` (which the main-thread rules require) would
    /// mean a marker that silently shifts by a day for a user who travels.
    static func string(routineId: UUID, day: Date) -> String {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let dayString = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        return "\(scheme)://\(routineHost)/\(routineId.uuidString)/\(occurrenceSegment)/\(dayString)"
    }

    /// The canonical form of a marker read back off an event, or `nil` when the
    /// string is not one of ours.
    ///
    /// Canonicalising rather than comparing raw strings makes the diff immune to
    /// spelling differences that mean the same thing (a lowercase UUID, say).
    /// Anything that fails to parse belongs to the *user* — they can add events
    /// to the app's calendar in Calendar.app — and is never touched.
    static func canonicalized(_ raw: String) -> String? {
        guard let url = URL(string: raw),
              url.scheme == scheme,
              url.host == routineHost else { return nil }
        // ["/", "<uuid>", "occurrence", "<yyyy-MM-dd>"]
        let components = url.pathComponents
        guard components.count == 4,
              components[2] == occurrenceSegment,
              let routineId = UUID(uuidString: components[1]),
              let day = dayComponents(from: components[3]) else { return nil }
        return "\(scheme)://\(routineHost)/\(routineId.uuidString)/\(occurrenceSegment)/"
            + String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }

    /// Strict `yyyy-MM-dd` parsing — three numeric fields of the right width and
    /// in range. Not a `DateFormatter`, for the time-zone reason above, and not
    /// a `Date`, because the diff only ever compares days as written.
    private static func dayComponents(from raw: String) -> (year: Int, month: Int, day: Int)? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (year, month, day)
    }
}

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
    static let minimumWindowDays = 400

    /// The span of calendar the mirror owns on this pass.
    ///
    /// **It starts today, so the past is never touched.** Events for days that
    /// have already passed are a record of what the user planned, and deleting
    /// them would quietly rewrite their calendar history every time a plan
    /// changed.
    static func mirrorWindow(
        desired: [PlannedWorkoutOccurrence],
        referenceDate: Date = Date()
    ) -> MirrorWindow {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let firstDay = calendar.startOfDay(for: referenceDate)
        let floor = calendar.date(byAdding: .day, value: minimumWindowDays, to: firstDay) ?? firstDay
        let furthest = desired.map({ calendar.startOfDay(for: $0.day) }).max() ?? firstDay
        return MirrorWindow(firstDay: firstDay, lastDay: max(floor, furthest), calendar: calendar)
    }

    /// The create/delete plan that turns `existing` into `desired`.
    ///
    /// Idempotent by construction: an unchanged plan matches every marker and
    /// yields no actions at all, so a repeat pass costs the user's calendar
    /// nothing — no churn, no CalDAV round-trips.
    ///
    /// Deletes come first so a shortened cadence frees its old days before the
    /// new ones are written.
    static func actions(
        desired: [PlannedWorkoutOccurrence],
        existing: [MirroredWorkoutEvent]
    ) -> [WorkoutCalendarMirrorAction] {
        // Deduplicate the desired side too: two markers can only collide when a
        // routine is planned twice for the same day, and the calendar shows one
        // event either way.
        var wanted: [String: PlannedWorkoutOccurrence] = [:]
        var order: [String] = []
        for occurrence in desired where wanted[occurrence.marker] == nil {
            wanted[occurrence.marker] = occurrence
            order.append(occurrence.marker)
        }

        var matched: Set<String> = []
        var deletes: [Int] = []
        for event in existing {
            guard let marker = event.markerURL.flatMap(PlannedWorkoutMarker.canonicalized) else {
                // Not ours: an event the user added to the app's calendar
                // themselves. Left exactly where it is.
                continue
            }
            if wanted[marker] != nil, !matched.contains(marker) {
                matched.insert(marker)
            } else {
                // Either the plan no longer wants this day, or it is a duplicate
                // of one already kept.
                deletes.append(event.reference)
            }
        }

        let creates = order.filter { !matched.contains($0) }.compactMap { wanted[$0] }
        return deletes.map { .delete(reference: $0) } + creates.map { .create($0) }
    }
}
