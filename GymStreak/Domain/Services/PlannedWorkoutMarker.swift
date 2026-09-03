//
//  PlannedWorkoutMarker.swift
//  GymStreak
//
//  The `gymstreak://` stamp written into every event the calendar mirror
//  creates, and the parser that reads it back. Pure Foundation.
//  See docs/calendar-sync.md §11b.
//

import Foundation

/// The stamp that gives every written event its identity — one form per plan
/// shape:
///
/// - `gymstreak://routine/<uuid>/occurrence/<yyyy-MM-dd>` — one dated session of
///   a cadence plan.
/// - `gymstreak://routine/<uuid>/series` — the whole repeating event of a
///   weekday plan. No day, because one event covers every occurrence.
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

    /// What a marker read off an event turns out to identify.
    ///
    /// Carries the canonical spelling rather than the raw string so the diff is
    /// immune to differences that mean the same thing (a lowercase UUID, say).
    enum Identity: Equatable, Sendable {
        case occurrence(canonical: String)
        case series(canonical: String)
    }

    private static let scheme = "gymstreak"
    private static let routineHost = "routine"
    private static let occurrenceSegment = "occurrence"
    private static let seriesSegment = "series"

    /// The marker for a routine's occurrence on a given day.
    ///
    /// The day is rendered from `Calendar` components rather than a
    /// `DateFormatter`: a formatter caches its time zone at construction, and
    /// hoisting one as a `static let` (which the main-thread rules require) would
    /// mean a marker that silently shifts by a day for a user who travels.
    static func occurrenceString(routineId: UUID, day: Date) -> String {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let dayString = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        return "\(scheme)://\(routineHost)/\(routineId.uuidString)/\(occurrenceSegment)/\(dayString)"
    }

    /// The marker for a routine's whole repeating series.
    static func seriesString(routineId: UUID) -> String {
        "\(scheme)://\(routineHost)/\(routineId.uuidString)/\(seriesSegment)"
    }

    /// What a marker read back off an event identifies, or `nil` when the string
    /// is not one of ours.
    ///
    /// Anything that fails to parse belongs to the *user* — they can add events
    /// to the app's calendar in Calendar.app — and is never touched.
    static func identity(of raw: String) -> Identity? {
        guard let url = URL(string: raw),
              url.scheme == scheme,
              url.host == routineHost else { return nil }
        // ["/", "<uuid>", "series"] or ["/", "<uuid>", "occurrence", "<yyyy-MM-dd>"]
        let components = url.pathComponents
        guard components.count >= 3,
              let routineId = UUID(uuidString: components[1]) else { return nil }

        switch components.count {
        case 3 where components[2] == seriesSegment:
            return .series(canonical: seriesString(routineId: routineId))
        case 4 where components[2] == occurrenceSegment:
            guard let day = dayComponents(from: components[3]) else { return nil }
            let dayString = String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
            return .occurrence(
                canonical: "\(scheme)://\(routineHost)/\(routineId.uuidString)/"
                    + "\(occurrenceSegment)/\(dayString)"
            )
        default:
            return nil
        }
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
