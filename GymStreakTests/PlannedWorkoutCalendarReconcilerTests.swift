//
//  PlannedWorkoutCalendarReconcilerTests.swift
//  GymStreakTests
//
//  The calendar mirror's decision-making, exercised without EventKit: the
//  marker that carries an event's identity, the window the pass owns, and the
//  create/delete diff itself. No `EKEventStore` is constructed here — that is
//  what the pure `Domain/` seam buys.
//

import Testing
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct PlannedWorkoutCalendarReconcilerTests {

    // MARK: - Fixtures

    private static let routineA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let routineB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let calendar = HistoryStatsService.isoGermanCalendar()
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func occurrence(
        _ routineId: UUID,
        _ year: Int, _ month: Int, _ dayOfMonth: Int,
        title: String = "Push Workout"
    ) -> PlannedWorkoutOccurrence {
        PlannedWorkoutOccurrence(
            routineId: routineId,
            day: day(year, month, dayOfMonth),
            title: title
        )
    }

    private func event(_ reference: Int, marker: String?) -> MirroredWorkoutEvent {
        MirroredWorkoutEvent(reference: reference, markerURL: marker)
    }

    // MARK: - Marker

    @Test("The marker carries the routine and the day")
    func markerFormat() {
        let marker = PlannedWorkoutMarker.string(routineId: Self.routineA, day: day(2026, 9, 7))
        #expect(marker == "gymstreak://routine/\(Self.routineA.uuidString)/occurrence/2026-09-07")
    }

    @Test("A marker read back off an event canonicalizes to the written form")
    func markerRoundTrips() {
        let written = PlannedWorkoutMarker.string(routineId: Self.routineA, day: day(2026, 12, 31))
        #expect(PlannedWorkoutMarker.canonicalized(written) == written)
    }

    @Test("A lowercase UUID is the same marker")
    func markerIsCaseInsensitiveOnTheUUID() {
        let written = PlannedWorkoutMarker.string(routineId: Self.routineA, day: day(2026, 9, 7))
        let lowercased = "gymstreak://routine/\(Self.routineA.uuidString.lowercased())/occurrence/2026-09-07"
        #expect(PlannedWorkoutMarker.canonicalized(lowercased) == written)
    }

    @Test(
        "Anything that is not one of our markers does not parse",
        arguments: [
            "https://example.com/routine/x/occurrence/2026-09-07",
            "gymstreak://exercise/AAAAAAAA-0000-0000-0000-000000000001/occurrence/2026-09-07",
            "gymstreak://routine/not-a-uuid/occurrence/2026-09-07",
            "gymstreak://routine/AAAAAAAA-0000-0000-0000-000000000001/occurrence/2026-9-7",
            "gymstreak://routine/AAAAAAAA-0000-0000-0000-000000000001/occurrence/2026-13-07",
            "gymstreak://routine/AAAAAAAA-0000-0000-0000-000000000001/occurrence",
            "not a url at all %%%"
        ]
    )
    func foreignMarkersDoNotParse(raw: String) {
        #expect(PlannedWorkoutMarker.canonicalized(raw) == nil)
    }

    // MARK: - Window

    @Test("The window starts today, so past events are never in scope")
    func windowStartsToday() {
        let today = day(2026, 9, 2)
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(desired: [], referenceDate: today)

        #expect(window.firstDay == today)
        #expect(window.covers(startOfDay: today))
        #expect(!window.covers(startOfDay: day(2026, 9, 1)))
    }

    @Test("The window reaches past the furthest planned occurrence")
    func windowCoversTheFurthestOccurrence() {
        let today = day(2026, 9, 2)
        let far = occurrence(Self.routineA, 2029, 1, 1)
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(
            desired: [far],
            referenceDate: today
        )

        #expect(window.covers(startOfDay: far.day))
        #expect(!window.covers(startOfDay: day(2029, 1, 2)))
        // The query range is deliberately a day wider on each side than the
        // window it filters back down to.
        #expect(window.queryStart < window.firstDay)
        #expect(window.queryEnd > window.lastDay)
    }

    @Test("With nothing planned the window still spans the cleanup floor")
    func windowFallsBackToTheFloor() {
        let today = day(2026, 9, 2)
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(desired: [], referenceDate: today)
        let calendar = HistoryStatsService.isoGermanCalendar()
        let floor = calendar.date(
            byAdding: .day,
            value: PlannedWorkoutCalendarReconciler.minimumWindowDays,
            to: today
        )!

        #expect(window.lastDay == floor)
    }

    // MARK: - Diff

    @Test("An empty calendar gets every planned occurrence")
    func createsEverythingWhenTheCalendarIsEmpty() {
        let desired = [occurrence(Self.routineA, 2026, 9, 2), occurrence(Self.routineA, 2026, 9, 7)]

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: desired, existing: [])

        #expect(actions == desired.map { .create($0) })
    }

    @Test("An unchanged plan writes and deletes nothing")
    func unchangedPlanIsANoOp() {
        let desired = [occurrence(Self.routineA, 2026, 9, 2), occurrence(Self.routineA, 2026, 9, 7)]
        let existing = desired.enumerated().map { event($0.offset, marker: $0.element.marker) }

        #expect(PlannedWorkoutCalendarReconciler.actions(desired: desired, existing: existing).isEmpty)
    }

    @Test("Clearing the plan deletes the routine's events and nothing else")
    func removedPlanDeletesItsEvents() {
        let gone = [occurrence(Self.routineA, 2026, 9, 2), occurrence(Self.routineA, 2026, 9, 7)]
        let kept = occurrence(Self.routineB, 2026, 9, 3)
        let existing = [
            event(0, marker: gone[0].marker),
            event(1, marker: kept.marker),
            event(2, marker: gone[1].marker)
        ]

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: [kept], existing: existing)

        #expect(actions == [.delete(reference: 0), .delete(reference: 2)])
    }

    @Test("Editing the interval deletes the old days before writing the new ones")
    func changedPlanMixesDeletesAndCreates() {
        let old = occurrence(Self.routineA, 2026, 9, 7)
        let kept = occurrence(Self.routineA, 2026, 9, 2)
        let new = occurrence(Self.routineA, 2026, 9, 4)
        let existing = [event(0, marker: kept.marker), event(1, marker: old.marker)]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: [kept, new],
            existing: existing
        )

        #expect(actions == [.delete(reference: 1), .create(new)])
    }

    @Test("Two planned routines are independent of each other")
    func routinesDoNotDisturbEachOther() {
        let a = occurrence(Self.routineA, 2026, 9, 2, title: "Push Workout")
        let bOld = occurrence(Self.routineB, 2026, 9, 3, title: "Pull Workout")
        let bNew = occurrence(Self.routineB, 2026, 9, 5, title: "Pull Workout")
        let existing = [event(0, marker: a.marker), event(1, marker: bOld.marker)]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: [a, bNew],
            existing: existing
        )

        #expect(actions == [.delete(reference: 1), .create(bNew)])
    }

    @Test("An event the user added to the calendar themselves is left alone")
    func unmarkedEventsAreNeverTouched() {
        let planned = occurrence(Self.routineA, 2026, 9, 2)
        let existing = [
            event(0, marker: nil),
            event(1, marker: "https://example.com/dentist"),
            event(2, marker: planned.marker)
        ]

        #expect(PlannedWorkoutCalendarReconciler.actions(desired: [planned], existing: existing).isEmpty)
    }

    @Test("A duplicated event is collapsed to one")
    func duplicateEventsAreCollapsed() {
        let planned = occurrence(Self.routineA, 2026, 9, 2)
        let existing = [
            event(0, marker: planned.marker),
            event(1, marker: planned.marker)
        ]

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: [planned], existing: existing)

        #expect(actions == [.delete(reference: 1)])
    }
}
