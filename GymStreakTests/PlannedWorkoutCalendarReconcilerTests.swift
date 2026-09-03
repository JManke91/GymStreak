//
//  PlannedWorkoutCalendarReconcilerTests.swift
//  GymStreakTests
//
//  The calendar mirror's decision-making, exercised without EventKit: the
//  markers that carry an event's identity in both plan shapes, the window the
//  pass owns, and the create/delete diff itself — including a routine moving
//  between the cadence and weekday shapes. No `EKEventStore` is constructed
//  here — that is what the pure `Domain/` seam buys.
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

    private func series(
        _ routineId: UUID,
        weekdays: Set<Int>,
        firstDay: Date? = nil,
        title: String = "Push Workout"
    ) -> PlannedWorkoutSeries {
        PlannedWorkoutSeries(
            routineId: routineId,
            weekdays: weekdays,
            firstDay: firstDay ?? day(2026, 9, 7),
            title: title
        )
    }

    /// A repeating event already in the calendar, as the gateway projects one.
    private func seriesEvent(
        _ reference: Int,
        _ routineId: UUID,
        weekdays: Set<Int>
    ) -> MirroredWorkoutEvent {
        MirroredWorkoutEvent(
            reference: reference,
            markerURL: PlannedWorkoutMarker.seriesString(routineId: routineId),
            recurringWeekdays: weekdays
        )
    }

    private func state(
        _ occurrences: [PlannedWorkoutOccurrence] = [],
        series: [PlannedWorkoutSeries] = []
    ) -> PlannedWorkoutCalendarState {
        PlannedWorkoutCalendarState(occurrences: occurrences, series: series)
    }

    // MARK: - Marker

    @Test("The occurrence marker carries the routine and the day")
    func markerFormat() {
        let marker = PlannedWorkoutMarker.occurrenceString(
            routineId: Self.routineA, day: day(2026, 9, 7)
        )
        #expect(marker == "gymstreak://routine/\(Self.routineA.uuidString)/occurrence/2026-09-07")
    }

    @Test("The series marker carries the routine and no day at all")
    func seriesMarkerFormat() {
        let marker = PlannedWorkoutMarker.seriesString(routineId: Self.routineA)
        #expect(marker == "gymstreak://routine/\(Self.routineA.uuidString)/series")
    }

    @Test("A marker read back off an event canonicalizes to the written form")
    func markerRoundTrips() {
        let written = PlannedWorkoutMarker.occurrenceString(
            routineId: Self.routineA, day: day(2026, 12, 31)
        )
        #expect(PlannedWorkoutMarker.identity(of: written) == .occurrence(canonical: written))
    }

    @Test("A series marker reads back as a series, never as an occurrence")
    func seriesMarkerRoundTrips() {
        let written = PlannedWorkoutMarker.seriesString(routineId: Self.routineA)
        #expect(PlannedWorkoutMarker.identity(of: written) == .series(canonical: written))
    }

    @Test("A lowercase UUID is the same marker, in both shapes")
    func markerIsCaseInsensitiveOnTheUUID() {
        let uuid = Self.routineA.uuidString
        let occurrence = PlannedWorkoutMarker.occurrenceString(
            routineId: Self.routineA, day: day(2026, 9, 7)
        )
        #expect(
            PlannedWorkoutMarker.identity(
                of: "gymstreak://routine/\(uuid.lowercased())/occurrence/2026-09-07"
            ) == .occurrence(canonical: occurrence)
        )
        #expect(
            PlannedWorkoutMarker.identity(of: "gymstreak://routine/\(uuid.lowercased())/series")
                == .series(canonical: PlannedWorkoutMarker.seriesString(routineId: Self.routineA))
        )
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
            "gymstreak://routine/AAAAAAAA-0000-0000-0000-000000000001/series/2026-09-07",
            "gymstreak://routine/AAAAAAAA-0000-0000-0000-000000000001/serie",
            "not a url at all %%%"
        ]
    )
    func foreignMarkersDoNotParse(raw: String) {
        #expect(PlannedWorkoutMarker.identity(of: raw) == nil)
    }

    // MARK: - Window

    @Test("The window starts today, so past events are never in scope")
    func windowStartsToday() {
        let today = day(2026, 9, 2)
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(desired: state(), referenceDate: today)

        #expect(window.firstDay == today)
        #expect(window.covers(startOfDay: today))
        #expect(!window.covers(startOfDay: day(2026, 9, 1)))
    }

    @Test("The window reaches past the furthest planned occurrence")
    func windowCoversTheFurthestOccurrence() {
        let today = day(2026, 9, 2)
        let far = occurrence(Self.routineA, 2029, 1, 1)
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(
            desired: state([far]),
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
        let window = PlannedWorkoutCalendarReconciler.mirrorWindow(desired: state(), referenceDate: today)
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

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: state(desired), existing: [])

        #expect(actions == desired.map { .create($0) })
    }

    @Test("An unchanged plan writes and deletes nothing")
    func unchangedPlanIsANoOp() {
        let desired = [occurrence(Self.routineA, 2026, 9, 2), occurrence(Self.routineA, 2026, 9, 7)]
        let existing = desired.enumerated().map { event($0.offset, marker: $0.element.marker) }

        #expect(PlannedWorkoutCalendarReconciler.actions(desired: state(desired), existing: existing).isEmpty)
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

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: state([kept]), existing: existing)

        #expect(actions == [.delete(reference: 0), .delete(reference: 2)])
    }

    @Test("Editing the interval deletes the old days before writing the new ones")
    func changedPlanMixesDeletesAndCreates() {
        let old = occurrence(Self.routineA, 2026, 9, 7)
        let kept = occurrence(Self.routineA, 2026, 9, 2)
        let new = occurrence(Self.routineA, 2026, 9, 4)
        let existing = [event(0, marker: kept.marker), event(1, marker: old.marker)]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state([kept, new]),
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
            desired: state([a, bNew]),
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

        #expect(PlannedWorkoutCalendarReconciler.actions(desired: state([planned]), existing: existing).isEmpty)
    }

    @Test("A duplicated event is collapsed to one")
    func duplicateEventsAreCollapsed() {
        let planned = occurrence(Self.routineA, 2026, 9, 2)
        let existing = [
            event(0, marker: planned.marker),
            event(1, marker: planned.marker)
        ]

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: state([planned]), existing: existing)

        #expect(actions == [.delete(reference: 1)])
    }

    // MARK: - Diff: the weekday series

    @Test("A weekday plan with no series yet gets one repeating event")
    func createsTheSeriesWhenTheCalendarIsEmpty() {
        let split = series(Self.routineA, weekdays: [1, 3, 5])

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state(series: [split]),
            existing: []
        )

        #expect(actions == [.createSeries(split)])
    }

    @Test("An unchanged weekday plan writes and deletes nothing")
    func unchangedSeriesIsANoOp() {
        let split = series(Self.routineA, weekdays: [1, 3, 5])
        let existing = [seriesEvent(0, Self.routineA, weekdays: [1, 3, 5])]

        #expect(
            PlannedWorkoutCalendarReconciler
                .actions(desired: state(series: [split]), existing: existing)
                .isEmpty
        )
    }

    @Test("A series whose start date has moved on is still left alone")
    func seriesIsMatchedOnThePatternNotTheStartDate() {
        // `nextDue` walks forward every day, so the desired first day moves even
        // when the plan does not. Rewriting the series for that would churn the
        // user's calendar daily — the open-ended weekly rule produces the same
        // upcoming days regardless of which past week it started in.
        let split = series(Self.routineA, weekdays: [1, 3, 5], firstDay: day(2027, 4, 14))
        let existing = [seriesEvent(0, Self.routineA, weekdays: [1, 3, 5])]

        #expect(
            PlannedWorkoutCalendarReconciler
                .actions(desired: state(series: [split]), existing: existing)
                .isEmpty
        )
    }

    @Test("Changing the selected weekdays replaces the series rather than editing it")
    func changedWeekdaysReplaceTheSeries() {
        let updated = series(Self.routineA, weekdays: [1, 3, 6])
        let existing = [seriesEvent(0, Self.routineA, weekdays: [1, 3, 5])]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state(series: [updated]),
            existing: existing
        )

        // Remove first, then write fresh — `EKRecurrenceRule` is immutable and
        // editing into a live series is the case Apple leaves undocumented.
        #expect(actions == [.deleteSeries(reference: 0), .createSeries(updated)])
    }

    @Test("Removing the plan removes the series")
    func removedWeekdayPlanDeletesItsSeries() {
        let existing = [seriesEvent(0, Self.routineA, weekdays: [1, 3, 5])]

        let actions = PlannedWorkoutCalendarReconciler.actions(desired: state(), existing: existing)

        #expect(actions == [.deleteSeries(reference: 0)])
    }

    @Test("A repeating event with no rule left on it is not mistaken for a match")
    func seriesWithoutARecurrenceIsRewritten() {
        let split = series(Self.routineA, weekdays: [1, 3, 5])
        // The user deleted the repeat in Calendar.app, leaving one dated event
        // behind the app's marker.
        let existing = [
            MirroredWorkoutEvent(
                reference: 0,
                markerURL: PlannedWorkoutMarker.seriesString(routineId: Self.routineA)
            )
        ]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state(series: [split]),
            existing: existing
        )

        #expect(actions == [.deleteSeries(reference: 0), .createSeries(split)])
    }

    @Test("A duplicated series is collapsed to one")
    func duplicateSeriesAreCollapsed() {
        let split = series(Self.routineA, weekdays: [1, 3, 5])
        let existing = [
            seriesEvent(0, Self.routineA, weekdays: [1, 3, 5]),
            seriesEvent(1, Self.routineA, weekdays: [1, 3, 5])
        ]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state(series: [split]),
            existing: existing
        )

        #expect(actions == [.deleteSeries(reference: 1)])
    }

    // MARK: - Diff: switching between the two shapes

    @Test("Weekdays → cadence leaves exactly a rolling window and no series")
    func weekdaysToCadenceSwapsTheRepresentation() {
        let window = [occurrence(Self.routineA, 2026, 9, 2), occurrence(Self.routineA, 2026, 9, 7)]
        let existing = [seriesEvent(0, Self.routineA, weekdays: [1, 3, 5])]

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state(window),
            existing: existing
        )

        #expect(actions == [.deleteSeries(reference: 0)] + window.map { .create($0) })
    }

    @Test("Cadence → weekdays leaves exactly a series and no one-shot events")
    func cadenceToWeekdaysSwapsTheRepresentation() {
        let split = series(Self.routineA, weekdays: [2, 4])
        let old = [occurrence(Self.routineA, 2026, 9, 2), occurrence(Self.routineA, 2026, 9, 7)]
        let existing = old.enumerated().map { event($0.offset, marker: $0.element.marker) }

        let actions = PlannedWorkoutCalendarReconciler.actions(
            desired: state(series: [split]),
            existing: existing
        )

        #expect(
            actions == [.delete(reference: 0), .delete(reference: 1), .createSeries(split)]
        )
    }

    @Test("A cadence routine and a weekday routine do not disturb each other")
    func bothShapesCoexist() {
        let cadence = occurrence(Self.routineA, 2026, 9, 2)
        let split = series(Self.routineB, weekdays: [1, 3, 5], title: "Pull Workout")
        let existing = [
            event(0, marker: cadence.marker),
            seriesEvent(1, Self.routineB, weekdays: [1, 3, 5])
        ]

        #expect(
            PlannedWorkoutCalendarReconciler
                .actions(desired: state([cadence], series: [split]), existing: existing)
                .isEmpty
        )
    }
}
