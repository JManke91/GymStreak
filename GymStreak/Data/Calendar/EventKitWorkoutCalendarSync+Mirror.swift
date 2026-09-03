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

    func mirror(_ desired: PlannedWorkoutCalendarState) throws {
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

        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(desired: desired)
        let events = readMirroredEvents(in: calendar, window: window)

        let existing = events.enumerated().map { index, event in
            MirroredWorkoutEvent(
                reference: index,
                markerURL: event.url?.absoluteString,
                recurringWeekdays: WorkoutCalendarRecurrence.isoWeekdays(ofRules: event.recurrenceRules)
            )
        }

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: desired,
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
                case .deleteSeries(let reference):
                    guard events.indices.contains(reference) else { continue }
                    // **`.futureEvents`, from the first occurrence inside the
                    // window** — which is today or later, so occurrences that
                    // have already happened stay in the user's calendar as the
                    // record of what they planned.
                    try eventStore.remove(events[reference], span: .futureEvents, commit: false)
                case .create(let occurrence):
                    let event = makeAllDayEvent(
                        titled: occurrence.title,
                        on: occurrence.day,
                        marker: occurrence.marker,
                        in: calendar
                    )
                    try eventStore.save(event, span: .thisEvent, commit: false)
                case .createSeries(let series):
                    let event = makeAllDayEvent(
                        titled: series.title,
                        on: series.firstDay,
                        marker: series.marker,
                        in: calendar
                    )
                    event.recurrenceRules = WorkoutCalendarRecurrence
                        .weeklyRule(isoWeekdays: series.weekdays).map { [$0] }
                    // `.futureEvents` on a brand-new event, because a series is
                    // being written as a whole rather than one occurrence of it.
                    try eventStore.save(event, span: .futureEvents, commit: false)
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

    /// Everything in the app's calendar this pass is allowed to act on, in
    /// **start-date order**, with a repeating event collapsed to its earliest
    /// in-window occurrence.
    ///
    /// `events(matching:)` expands a recurrence, so one Mon/Wed/Fri series comes
    /// back as ~170 separate `EKEvent`s across the window — all sharing an
    /// `eventIdentifier`, which Apple documents is "the same for all
    /// occurrences". Diffing them as ~170 events would delete the series 169
    /// times over, so only one occurrence of each series survives here.
    ///
    /// **Which one is load-bearing, and the sort is not decoration.** The kept
    /// occurrence becomes the handle for a `.futureEvents` removal, which takes
    /// the series from *that* occurrence onward and leaves everything before it
    /// standing. `EKEventStore.h` is explicit that `eventsMatchingPredicate:`
    /// returns "an array of EKEvent objects, or nil. There is no guaranteed
    /// order to the events" — so keeping whichever occurrence happened to come
    /// back first would, on any pass where that is not the earliest, truncate the
    /// old series mid-window and leave its stale days sitting beside the freshly
    /// written one. Sorting by `startDate` first is what makes "the earliest
    /// occurrence the mirror owns" true rather than hoped for.
    private func readMirroredEvents(in calendar: EKCalendar, window: MirrorWindow) -> [EKEvent] {
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
        ).sorted { $0.startDate < $1.startDate }
        // All-day events come back normalized into the default time zone, so the
        // day — never the `Date` — is what the window is asked about. One
        // `Calendar`, not one per event.
        let dayCalendar = HistoryStatsService.isoGermanCalendar()
        var seenSeries: Set<String> = []
        var result: [EKEvent] = []
        for event in candidates
        where window.covers(startOfDay: dayCalendar.startOfDay(for: event.startDate)) {
            if event.hasRecurrenceRules {
                // `eventIdentifier` is `null_unspecified` in the SDK header, so
                // the marker stands in when it is absent. It identifies a series
                // just as well — one per routine — and collapsing on *something*
                // matters: two uncollapsed occurrences of one series both carry
                // that marker, so the diff would keep the first and emit
                // `.deleteSeries` for the second, truncating the very series it
                // just decided to keep, with no create to restore it. An event
                // with neither is not one the app wrote and is left whole; the
                // reconciler ignores it for want of a marker anyway.
                if let key = event.eventIdentifier ?? event.url?.absoluteString {
                    guard seenSeries.insert(key).inserted else { continue }
                }
            }
            result.append(event)
        }
        return result
    }

    /// One planned day, as an **all-day event with no alarm**.
    ///
    /// A plan carries a date and no time of day, so inventing one would assert
    /// something the app never captured; an all-day event also does not block the
    /// user's day or attract travel-time suggestions. No `EKAlarm` for a related
    /// reason: an alarm would quietly deliver the deferred planned-workout
    /// reminder (docs/workout-planning.md § "Deferred to phase 2") through a
    /// different mechanism than that design chose, which is a product decision to
    /// take on its own rather than a line to slip in here.
    ///
    /// Shared by both shapes: a series is exactly this event plus a recurrence
    /// rule, and its `startDate` is the first occurrence.
    ///
    /// The marker in `url` is what makes the event findable on the next pass —
    /// see `PlannedWorkoutMarker`.
    private func makeAllDayEvent(
        titled title: String,
        on day: Date,
        marker: String,
        in calendar: EKCalendar
    ) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.isAllDay = true
        // **`endDate` is the last day, inclusive** — unlike RFC 5545's exclusive
        // `DTEND`, so the *next* day here would render as a two-day event. Apple
        // documents nothing about `endDate` under `isAllDay`, so this is
        // empirical and is verified on device rather than assumed
        // (docs/calendar-sync.md §11). Equal dates do not trip
        // `EKErrorDatesInverted`, which fires only when end precedes start.
        event.startDate = day
        event.endDate = day
        // `nil` is Apple's documented meaning of a *floating* event — one not
        // tied to a time zone — and the header calls all-day events floating.
        // Pinning `TimeZone.current` instead would give the event a zone it
        // should not have, and how EventKit normalises that combination is
        // undocumented.
        event.timeZone = nil
        event.url = URL(string: marker)
        return event
    }
}
