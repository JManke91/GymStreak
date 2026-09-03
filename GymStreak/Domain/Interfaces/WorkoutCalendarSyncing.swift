//
//  WorkoutCalendarSyncing.swift
//  GymStreak
//
//  What the app needs from the Apple Calendar gateway: the permission
//  handshake and ownership of a dedicated "GymStreak" calendar. Lets
//  Presentation depend on a protocol instead of `EKEventStore`, and keeps
//  EventKit out of `Domain/` entirely. See docs/calendar-sync.md.
//

import Foundation

/// The app's own view of Calendar authorization.
///
/// Deliberately *not* `EKAuthorizationStatus`: `Domain/` must not import
/// EventKit, and the app only ever cares about "can we own and revise a
/// calendar or not". EventKit's `.writeOnly` collapses into `.denied` here —
/// a write-only app cannot enumerate a source to own a calendar on and can
/// never find the events it wrote, so the remedy is the same Settings trip.
enum CalendarAccessStatus: Sendable, Equatable {
    /// Never asked. The one state in which a prompt appears.
    case notDetermined
    /// Refused, or granted only "Add Only" — the feature cannot work.
    case denied
    /// Withheld by a profile or Screen Time; the user cannot grant it.
    case restricted
    /// Everything the feature needs.
    case fullAccess
}

/// Owner of the app's dedicated Apple Calendar.
///
/// `@MainActor` because the only conformer confines a non-`Sendable`
/// `EKEventStore` (rule 2 of docs/swift6-concurrency.md).
@MainActor
protocol WorkoutCalendarSyncing: AnyObject {

    /// Current authorization, read fresh from the system every time — the user
    /// can revoke it in Settings while the app is suspended.
    var accessStatus: CalendarAccessStatus { get }

    /// Identifier of the app-owned calendar, or `nil` when the app owns none.
    /// Non-`nil` does not prove the calendar still exists: the user can delete
    /// it in Calendar.app, which no API notifies us about (ticket 03).
    var appCalendarIdentifier: String? { get }

    /// Asks for full Calendar access if it has not been decided, then makes
    /// sure the app-owned calendar exists.
    ///
    /// Idempotent: a second call reuses the persisted calendar rather than
    /// creating a second one, and an identifier that no longer resolves is
    /// treated as "create a new one". Never prompts twice — once the system
    /// has a decision on file, `requestFullAccessToEvents()` returns it
    /// without showing anything.
    ///
    /// - Throws: `WorkoutCalendarSyncError` — the caller is expected to leave
    ///   the feature switched off when this throws.
    func enable() async throws

    /// Brings the app-owned calendar into the given state and removes the events
    /// it wrote that the plan no longer wants.
    ///
    /// Both plan shapes travel in one value: a cadence plan's rolling window of
    /// one-shot days, and a fixed-weekday plan's single open-ended repeating
    /// event. A routine moving between the two is not a special case — it simply
    /// contributes to the other list, and the events of the shape it left are
    /// removed like any other unwanted ones.
    ///
    /// Idempotent: passing the same state twice writes and deletes nothing the
    /// second time. Only the app-owned calendar is read or written, and only
    /// events carrying the app's own marker are ever removed — an event the user
    /// added to that calendar themselves is left alone.
    ///
    /// A no-op when the app owns no calendar. When it owns one that no longer
    /// resolves — the user deleted it behind the app's back — this throws
    /// `.calendarMissing` rather than passing silently, because that is the only
    /// moment the app can find out.
    ///
    /// - Throws: `WorkoutCalendarSyncError`. The caller is expected to log and
    ///   carry on: the plan is the source of truth, the calendar a projection of
    ///   it, so a failed mirror must never undo a saved plan change.
    func mirror(_ desired: PlannedWorkoutCalendarState) throws

    /// Removes the app-owned calendar, taking every event the app ever wrote
    /// with it, and forgets its identifier.
    ///
    /// A no-op when the app owns no calendar, or when the one it owned is
    /// already gone. Never touches a calendar the app did not create.
    func disable() throws
}

// MARK: - Error Types

/// The failure vocabulary of the calendar gateway.
///
/// Declared alongside the protocol so `Presentation/` can classify a failure
/// without reaching into `Data/` — same arrangement as `HealthKitError`.
enum WorkoutCalendarSyncError: LocalizedError, Equatable {
    /// The user refused, granted "Add Only", or the permission is restricted.
    /// The remedy is a trip to Settings, not a retry.
    case accessDenied
    /// No account the app can own a calendar on — neither iCloud nor a local
    /// source came back. Vanishingly rare, and nothing the app can fix.
    case noWritableSource
    /// The app holds an identifier, but the calendar it names is gone: the user
    /// deleted it in Calendar.app or removed the account it lived on. No API
    /// announces that, so it is only ever discovered on a pass — and deleting a
    /// calendar is deliberate enough to be read as an opt-out rather than as
    /// something to repair (docs/calendar-sync.md §12).
    case calendarMissing
    /// EventKit refused the save or the delete.
    case calendarWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "GymStreak is not allowed full access to your calendars"
        case .noWritableSource:
            return "No calendar account is available to create a calendar on"
        case .calendarMissing:
            return "The GymStreak calendar no longer exists"
        case .calendarWriteFailed(let message):
            return "Failed to update the GymStreak calendar: \(message)"
        }
    }
}
