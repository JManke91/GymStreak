//
//  WorkoutCalendarAdoption.swift
//  GymStreak
//
//  The rule that decides whether an existing calendar is one this app created
//  in a previous install, and may therefore be adopted instead of creating a
//  second one. Pure and EventKit-free so it can be tested — the gateway that
//  owns the `EKEventStore` cannot be. See docs/calendar-sync.md §4a.
//

import Foundation

/// The few facts about a calendar the adoption rule needs, projected off
/// `EKCalendar` so this logic never touches EventKit.
struct WorkoutCalendarCandidate: Equatable {
    let identifier: String
    let sourceIdentifier: String
    let title: String
    let isWritable: Bool
}

enum WorkoutCalendarAdoption {

    /// The identifier of the calendar to adopt, or `nil` when none matches and
    /// a new one must be created.
    ///
    /// **Why this exists.** `calendarIdentifier` is persisted in `UserDefaults`,
    /// which iOS wipes when the app is deleted — so a reinstall found no handle
    /// and created a second "Gym Streak" calendar, then a third. Apple offers
    /// nothing better to key on: `calendarIdentifier` is **device-local** (the
    /// same iCloud calendar has a different one on the user's iPad and Mac) and
    /// a full sync can invalidate it, and there is no external/stable calendar
    /// identifier — `calendarItemExternalIdentifier` exists only on events.
    /// Carrying the identifier across devices via iCloud KVS would therefore
    /// resolve to `nil` on every *other* device and manufacture a duplicate per
    /// device, which is worse than the bug it set out to fix.
    ///
    /// So the match is made on what is actually stable: the calendar sits on the
    /// source the app would have created it on, carries the exact localized
    /// title the app uses, and is writable.
    ///
    /// **Title and writability are required; the source is only a preference.**
    /// A user may legitimately own a calendar named "Gym Streak", and adopting it
    /// would mean deleting it when they later switch sync off — so the title must
    /// match exactly and the calendar must be one the app could actually manage.
    ///
    /// The source, however, cannot be a *requirement*. `preferredSource()`
    /// resolves through `defaultCalendarForNewEvents`, which the user can change
    /// at any time in Settings → Calendar → Default Calendar. If they move it
    /// between the install that created the calendar and the reinstall that tries
    /// to adopt it, an exact-source requirement misses and a second "Gym Streak"
    /// calendar appears — precisely the bug this rule exists to prevent. So a
    /// match on the expected source is *preferred*, and a match elsewhere is
    /// still accepted rather than dropped.
    ///
    /// **On more than one match it adopts the lowest identifier rather than
    /// asking.** The choice only has to be deterministic and repeatable: every
    /// candidate is indistinguishable from the others by any fact EventKit
    /// exposes, so there is nothing to ask a *useful* question about, and the
    /// alternative — creating yet another calendar — is the exact behaviour this
    /// rule exists to stop. Note the ownership risk is not increased by the
    /// count: adopting a same-named user calendar is equally possible when it is
    /// the only match.
    static func adoptableCalendarIdentifier(
        from candidates: [WorkoutCalendarCandidate],
        sourceIdentifier: String,
        title: String
    ) -> String? {
        let matches = candidates.filter { $0.title == title && $0.isWritable }
        // Prefer the source the app would have used; fall back to any account
        // when the user has moved their default calendar since.
        let onExpectedSource = matches.filter { $0.sourceIdentifier == sourceIdentifier }
        let pool = onExpectedSource.isEmpty ? matches : onExpectedSource
        return pool.map(\.identifier).min()
    }
}
