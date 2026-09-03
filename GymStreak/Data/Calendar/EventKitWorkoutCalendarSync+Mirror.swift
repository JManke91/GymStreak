//
//  EventKitWorkoutCalendarSync+Mirror.swift
//  GymStreak
//
//  The event-writing half of the calendar gateway: read the app-owned calendar
//  back over the pass's window, ask the pure `Domain/` reconciler what to change,
//  and execute it as one batched commit. Split out of
//  `EventKitWorkoutCalendarSync.swift` to keep both files inside the size
//  guidance, following the `WatchTemplateTransactionService+…` precedent.
//  See docs/calendar-sync.md §11.
//

import EventKit
import Foundation

extension EventKitWorkoutCalendarSync {

    func mirror(occurrences: [PlannedWorkoutOccurrence]) throws {
        guard accessStatus == .fullAccess else {
            throw WorkoutCalendarSyncError.accessDenied
        }
        // No calendar at all means nothing to mirror into — and nothing to clean
        // up either, since every event the app ever wrote lives in that calendar.
        guard let identifier = appCalendarIdentifier else { return }
        // An identifier that no longer resolves is a different story: the user
        // deleted the app's calendar in Calendar.app, or removed the account it
        // lived on. Nothing notifies the app of that, so a pass is the only place
        // it can be found — and it is reported rather than passed over, because
        // the caller reads it as an opt-out (docs/calendar-sync.md §12).
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            throw WorkoutCalendarSyncError.calendarMissing
        }

        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(desired: occurrences)
        // Scoped to the app's own calendar, so no event outside it is ever read,
        // let alone written — even one that happens to carry a matching marker.
        //
        // `events(matching:)` rather than `enumerateEvents(matching:using:)`: the
        // `Sendable` status of `EKEventSearchCallback` is not documented, and an
        // array sidesteps the question entirely (docs/calendar-sync.md §5). It is
        // synchronous and blocking, and Apple suggests running it off the main
        // thread — which a non-`Sendable` `EKEventStore` makes impossible, so the
        // window stays bounded and the calendar array stays at one instead.
        //
        // The range is `window`'s widened one; the precise day filter below is
        // ours (see `MirrorWindow`).
        let candidates = eventStore.events(
            matching: eventStore.predicateForEvents(
                withStart: window.queryStart,
                end: window.queryEnd,
                calendars: [calendar]
            )
        )
        // All-day events come back normalized into the default time zone, so the
        // day — never the `Date` — is what the window is asked about. One
        // `Calendar`, not one per event.
        let dayCalendar = HistoryStatsService.isoGermanCalendar()
        let events = candidates.filter {
            window.covers(startOfDay: dayCalendar.startOfDay(for: $0.startDate))
        }

        let existing = events.enumerated().map { index, event in
            MirroredWorkoutEvent(reference: index, markerURL: event.url?.absoluteString)
        }

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: occurrences,
            existing: existing
        )
        guard !actions.isEmpty else { return }

        do {
            // Every write is buffered (`commit: false`) and one trailing
            // `commit()` sends the batch, so a plan change costs the user's
            // calendar a single round-trip instead of one per event.
            for action in actions {
                switch action {
                case .delete(let reference):
                    // The handle is an index into the very array `existing` was
                    // built from, so this always resolves — the guard is here so
                    // that if the two ever drift, the pass fails a delete rather
                    // than trapping.
                    guard events.indices.contains(reference) else { continue }
                    try eventStore.remove(events[reference], span: .thisEvent, commit: false)
                case .create(let occurrence):
                    try eventStore.save(
                        makeEvent(for: occurrence, in: calendar),
                        span: .thisEvent,
                        commit: false
                    )
                }
            }
            try eventStore.commit()
        } catch {
            // Apple: after a failed batch, "subsequent commits will fail until
            // the event store is manually reset", so the reset is mandatory
            // rather than tidy. It invalidates every object ever fetched from
            // this store — which is safe here only because each pass re-fetches
            // the calendar by identifier and holds no `EKEvent` across passes.
            // `EKError.calendarReadOnly` lands here too: the user can make even
            // an app-owned calendar read-only from another device.
            eventStore.reset()
            throw WorkoutCalendarSyncError.calendarWriteFailed(error.localizedDescription)
        }
    }

    /// One planned session, as an **all-day event with no alarm**.
    ///
    /// A plan carries a date and no time of day, so inventing one would assert
    /// something the app never captured; an all-day event also does not block the
    /// user's day or attract travel-time suggestions. No `EKAlarm` for a related
    /// reason: an alarm would quietly deliver the deferred planned-workout
    /// reminder (docs/workout-planning.md § "Deferred to phase 2") through a
    /// different mechanism than that design chose, which is a product decision to
    /// take on its own rather than a line to slip in here.
    ///
    /// The marker in `url` is what makes the event findable on the next pass —
    /// see `PlannedWorkoutMarker`.
    private func makeEvent(
        for occurrence: PlannedWorkoutOccurrence,
        in calendar: EKCalendar
    ) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = occurrence.title
        event.isAllDay = true
        // **`endDate` is the last day, inclusive** — unlike RFC 5545's exclusive
        // `DTEND`, so the *next* day here would render as a two-day event. Apple
        // documents nothing about `endDate` under `isAllDay`, so this is
        // empirical and is verified on device rather than assumed
        // (docs/calendar-sync.md §11). Equal dates do not trip
        // `EKErrorDatesInverted`, which fires only when end precedes start.
        event.startDate = occurrence.day
        event.endDate = occurrence.day
        // `nil` is Apple's documented meaning of a *floating* event — one not
        // tied to a time zone — and the header calls all-day events floating.
        // Pinning `TimeZone.current` instead would give the event a zone it
        // should not have, and how EventKit normalises that combination is
        // undocumented.
        event.timeZone = nil
        event.url = URL(string: occurrence.marker)
        return event
    }
}
