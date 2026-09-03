//
//  EventKitWorkoutCalendarSync.swift
//  GymStreak
//
//  The only file in the iOS target that imports EventKit, and the only owner
//  of the `EKEventStore`. Implements the permission handshake and ownership of
//  a dedicated "GymStreak" calendar. See docs/calendar-sync.md.
//

import EventKit
import Foundation
import UIKit

/// EventKit-backed owner of the app's dedicated calendar.
///
/// `@MainActor` because `EKEventStore` is not `Sendable` (its documented
/// conformances are `CVarArg`, `CustomDebugStringConvertible`,
/// `CustomStringConvertible`, `Equatable`, `Hashable`, `NSObjectProtocol` —
/// no `Sendable`), so it is confined per rule 2 of docs/swift6-concurrency.md.
/// The write volume here is a handful of events per plan change, not the
/// aggregation load that forced History onto a `@ModelActor`.
@MainActor
final class EventKitWorkoutCalendarSync: WorkoutCalendarSyncing {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let calendarIdentifier = "calendar_sync.calendar_identifier"
    }

    /// `DesignSystem.Colors.tint`, restated as a literal.
    ///
    /// `Data/` must not import `Presentation/`, and this is the one place a
    /// design token leaves the app — Calendar.app paints the calendar with it.
    /// Keep in step with `DesignSystem.swift` by hand.
    private static let calendarColor = UIColor(
        red: 0, green: 1, blue: 133 / 255, alpha: 1
    ).cgColor

    private let makeEventStore: () -> EKEventStore
    private let defaults: UserDefaults

    /// Built on first use, not at launch.
    ///
    /// This gateway is constructed in `AppDependencies.init()`, i.e. inside
    /// `GymStreakApp.init()`, for every user — including the majority who never
    /// switch calendar sync on. `EKEventStore()` opens a connection to the
    /// Calendar store and Apple documents it as relatively expensive, so an
    /// eager default argument would put that on the main thread of every cold
    /// launch to serve a feature most launches never touch.
    ///
    /// `accessStatus` deliberately reads the **static**
    /// `EKEventStore.authorizationStatus(for:)`, and `disable()` returns on the
    /// persisted identifier before touching this, so neither forces the store
    /// into existence. `lazy` is safe without synchronisation because the class
    /// is `@MainActor`-confined.
    ///
    /// Internal rather than `private` only because `private` is file-scoped and
    /// the mirroring half of this gateway lives in
    /// `EventKitWorkoutCalendarSync+Mirror.swift`. Nothing outside this type
    /// touches it — the `EKEventStore` still leaves `Data/Calendar/` nowhere.
    lazy var eventStore: EKEventStore = makeEventStore()

    // MARK: - Init

    /// - Parameter eventStore: an autoclosure so the default is *not* evaluated
    ///   at construction; see `eventStore` above. Still an injection point for
    ///   tests, which is why it stays in the signature.
    /// - Parameter defaults: injectable so the persisted calendar identifier
    ///   can be pointed at a throwaway suite.
    init(
        eventStore: @autoclosure @escaping () -> EKEventStore = EKEventStore(),
        defaults: UserDefaults = .standard
    ) {
        self.makeEventStore = eventStore
        self.defaults = defaults
    }

    // MARK: - WorkoutCalendarSyncing

    var accessStatus: CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .fullAccess:
            return .fullAccess
        case .denied, .writeOnly:
            // `.writeOnly` is reachable: iOS 17+ offers "Add Only" in
            // Settings → Privacy → Calendars. It is useless to this feature —
            // Apple: "requests for calendar lists return a single virtual
            // calendar, and queries for existing events return no results" —
            // so the app can neither own a calendar nor revise what it wrote.
            // Same remedy as a flat refusal, so the same case.
            return .denied
        @unknown default:
            return .denied
        }
    }

    var appCalendarIdentifier: String? {
        defaults.string(forKey: Keys.calendarIdentifier)
    }

    func enable() async throws {
        // Full access, not `requestWriteOnlyAccessToEvents()`: ticket 03 has to
        // find and revise events the app wrote earlier, which a write-only app
        // can never do. The `async throws -> Bool` variant is used because the
        // completion overloads fire on an arbitrary queue.
        //
        // This never prompts twice: once the system holds a decision, the call
        // returns it without presenting anything.
        //
        // Wrapped so only the app's own vocabulary leaves `Data/`: the
        // protocol documents that it throws `WorkoutCalendarSyncError`, and a
        // raw `EKError` crossing the Domain seam would land in the view model's
        // `default:` branch and be shown as "Apple Calendar refused the
        // change". A throw here is an access problem — a refusal comes back as
        // `false`, not as an error — so the Settings remedy is the right one.
        let granted: Bool
        do {
            granted = try await eventStore.requestFullAccessToEvents()
        } catch {
            throw WorkoutCalendarSyncError.accessDenied
        }
        // `granted` alone is not enough — it comes back `true` for a write-only
        // grant made earlier in Settings, which cannot carry this feature.
        guard granted, accessStatus == .fullAccess else {
            throw WorkoutCalendarSyncError.accessDenied
        }
        try ensureAppCalendarExists()
    }

    // `mirror(occurrences:)` lives in EventKitWorkoutCalendarSync+Mirror.swift —
    // this file owns the permission handshake and the calendar itself.

    func disable() throws {
        guard let identifier = appCalendarIdentifier else { return }

        // **The identifier is forgotten only once the calendar is actually
        // gone.** Clearing it up front orphans the calendar on every path where
        // the removal cannot happen: with access revoked or downgraded to "Add
        // Only", `calendar(withIdentifier:)` answers `nil`, so the app dropped
        // its only handle while the calendar lived on — and the next enable
        // built a second one. Found on device: toggling off and on across an
        // access change left three "Gym Streak" calendars behind, and switching
        // off then removed only the newest.
        guard accessStatus == .fullAccess else {
            // Keeping the identifier is what makes this recoverable: once the
            // user restores access, enable adopts the very same calendar
            // instead of stacking another one beside it.
            throw WorkoutCalendarSyncError.accessDenied
        }

        // Only ever the calendar this app created and recorded — a calendar the
        // app does not own has no identifier stored here and is unreachable
        // from this path.
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            // Full access, and it still does not resolve: the user deleted it in
            // Calendar.app. Genuinely gone, so the handle is safe to drop.
            defaults.removeObject(forKey: Keys.calendarIdentifier)
            return
        }

        do {
            try eventStore.removeCalendar(calendar, commit: true)
        } catch {
            // The calendar is still there, so the app keeps claiming it.
            throw WorkoutCalendarSyncError.calendarWriteFailed(error.localizedDescription)
        }
        defaults.removeObject(forKey: Keys.calendarIdentifier)
    }

    // MARK: - Calendar Ownership

    /// Reuses the persisted calendar, adopts one left by a previous install, or
    /// creates one — in that order.
    ///
    /// An identifier that no longer resolves means the user deleted the
    /// calendar in Calendar.app, removed the account, or **deleted the app**
    /// (which wipes `UserDefaults` while leaving the calendar in their iCloud
    /// account, since iOS runs no code at uninstall and the calendar is not in
    /// the app's container). Creating unconditionally at that point is what gave
    /// a reinstalling user a second "Gym Streak" calendar, then a third — so the
    /// adoption pass runs before the create. Detecting a deletion *while* sync
    /// is on is still ticket 03's job.
    private func ensureAppCalendarExists() throws {
        if let identifier = appCalendarIdentifier,
           eventStore.calendar(withIdentifier: identifier) != nil {
            return
        }

        guard let source = preferredSource() else {
            throw WorkoutCalendarSyncError.noWritableSource
        }

        let title = "calendar_sync.calendar.title".localized

        // Adopt a calendar this app created in a previous install rather than
        // stacking another one beside it. The rule itself is pure and tested in
        // `WorkoutCalendarAdoptionTests`; this only projects the values it needs.
        let candidates = eventStore.calendars(for: .event).map {
            WorkoutCalendarCandidate(
                identifier: $0.calendarIdentifier,
                // `EKCalendar.source` is `null_unspecified` in the SDK header
                // ("nil for new calendars until you set it"), so it imports as
                // `EKSource!`. Persisted calendars always carry one, but this is
                // a system boundary inside `enable()` — force-unwrapping would
                // crash the toggle rather than fail it. A calendar with no
                // source simply fails to match, which is the right outcome.
                sourceIdentifier: $0.source?.sourceIdentifier ?? "",
                title: $0.title,
                isWritable: $0.allowsContentModifications
            )
        }
        if let adopted = WorkoutCalendarAdoption.adoptableCalendarIdentifier(
            from: candidates,
            sourceIdentifier: source.sourceIdentifier,
            title: title
        ) {
            defaults.set(adopted, forKey: Keys.calendarIdentifier)
            return
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = title
        calendar.cgColor = Self.calendarColor
        calendar.source = source

        do {
            try eventStore.saveCalendar(calendar, commit: true)
        } catch {
            throw WorkoutCalendarSyncError.calendarWriteFailed(error.localizedDescription)
        }
        defaults.set(calendar.calendarIdentifier, forKey: Keys.calendarIdentifier)
    }

    /// Which account the calendar is created on — and therefore whether it
    /// reaches the user's iPad and Mac.
    ///
    /// Apple prescribes nothing here, so the rule is stated explicitly:
    /// 1. the source of the user's default calendar for new events — whatever
    ///    they already trust their own events to;
    /// 2. otherwise the iCloud CalDAV source, which is what makes the calendar
    ///    travel across devices;
    /// 3. otherwise a local source: correct when no account is signed in, and
    ///    the calendar simply stays on this device.
    ///
    /// This is CalDAV, entirely outside the app's `iCloud.com.jmanke.gymstreak`
    /// CloudKit container — no schema deploy is implicated.
    private func preferredSource() -> EKSource? {
        if let source = eventStore.defaultCalendarForNewEvents?.source {
            return source
        }
        if let iCloud = eventStore.sources.first(where: {
            $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud")
        }) {
            return iCloud
        }
        return eventStore.sources.first { $0.sourceType == .local }
    }
}
