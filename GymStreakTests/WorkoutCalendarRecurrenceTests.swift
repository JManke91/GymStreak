//
//  WorkoutCalendarRecurrenceTests.swift
//  GymStreakTests
//
//  The ISO ↔ `EKWeekday` boundary, all seven days in both directions, and the
//  open-ended weekly rule a fixed-weekday plan becomes. `EKRecurrenceRule` is a
//  standalone value object, so this needs no `EKEventStore` — which is why
//  `isoWeekdays(ofRules:)` takes the rules rather than the event.
//

import Testing
import EventKit
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutCalendarRecurrenceTests {

    // MARK: - The numbering boundary

    /// ISO 1 = Monday … 7 = Sunday against `EKWeekday`, whose 1 is Sunday.
    /// **Sunday is the case a naive `EKWeekday(rawValue: isoWeekday)` gets most
    /// visibly wrong** — it would answer Saturday — but the shift is wrong for
    /// all seven, so all seven are pinned here.
    @Test(
        "Every ISO weekday maps to the right EKWeekday",
        arguments: [
            (1, EKWeekday.monday),
            (2, EKWeekday.tuesday),
            (3, EKWeekday.wednesday),
            (4, EKWeekday.thursday),
            (5, EKWeekday.friday),
            (6, EKWeekday.saturday),
            (7, EKWeekday.sunday)
        ]
    )
    func isoMapsToEKWeekday(isoWeekday: Int, expected: EKWeekday) {
        #expect(WorkoutCalendarRecurrence.ekWeekday(fromISO: isoWeekday) == expected)
        // The raw values genuinely differ for every day, which is the whole trap.
        #expect(expected.rawValue != isoWeekday)
    }

    @Test(
        "Every EKWeekday maps back to the right ISO weekday",
        arguments: [
            (EKWeekday.sunday, 7),
            (EKWeekday.monday, 1),
            (EKWeekday.tuesday, 2),
            (EKWeekday.wednesday, 3),
            (EKWeekday.thursday, 4),
            (EKWeekday.friday, 5),
            (EKWeekday.saturday, 6)
        ]
    )
    func ekWeekdayMapsBackToISO(ekWeekday: EKWeekday, expected: Int) {
        #expect(WorkoutCalendarRecurrence.isoWeekday(from: ekWeekday) == expected)
    }

    @Test("An out-of-range ISO weekday maps to nothing rather than to a wrong day")
    func outOfRangeISOWeekdayIsRejected() {
        #expect(WorkoutCalendarRecurrence.ekWeekday(fromISO: 0) == nil)
        #expect(WorkoutCalendarRecurrence.ekWeekday(fromISO: 8) == nil)
    }

    @Test("The ISO numbering is the one WorkoutPlanningService already speaks")
    func isoNumberingAgreesWithThePlanner() throws {
        // Belt and braces on the mapping's premise: a Sunday really is ISO 7
        // everywhere in this app, so `.sunday` is the right EventKit answer.
        let calendar = HistoryStatsService.isoGermanCalendar()
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
        #expect(WorkoutPlanningService.isoWeekday(from: sunday, calendar: calendar) == 7)
        #expect(WorkoutCalendarRecurrence.ekWeekday(fromISO: 7) == .sunday)
    }

    // MARK: - The rule

    @Test("A weekday plan becomes an open-ended weekly rule on exactly those days")
    func weeklyRuleShape() throws {
        let rule = try #require(WorkoutCalendarRecurrence.weeklyRule(isoWeekdays: [1, 3, 5]))

        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 1)
        // Open-ended is the point: the occurrences keep coming for a user who
        // does not open the app for months.
        #expect(rule.recurrenceEnd == nil)
        let days = try #require(rule.daysOfTheWeek)
        #expect(Set(days.map(\.dayOfTheWeek)) == [.monday, .wednesday, .friday])
        #expect(days.allSatisfy { $0.weekNumber == 0 })
    }

    @Test("A Sunday-only plan produces a Sunday rule")
    func sundayOnlyRule() throws {
        let rule = try #require(WorkoutCalendarRecurrence.weeklyRule(isoWeekdays: [7]))
        let days = try #require(rule.daysOfTheWeek)
        #expect(days.map(\.dayOfTheWeek) == [.sunday])
    }

    @Test("No selected weekday is not a plan and produces no rule")
    func emptyWeekdaysProduceNoRule() {
        #expect(WorkoutCalendarRecurrence.weeklyRule(isoWeekdays: []) == nil)
    }

    // MARK: - Reading the pattern back

    @Test("A rule this app wrote round-trips to the same ISO weekdays", arguments: [
        Set([1]), Set([7]), Set([1, 3, 5]), Set([6, 7]), Set(1...7)
    ])
    func ruleRoundTrips(weekdays: Set<Int>) throws {
        let rule = try #require(WorkoutCalendarRecurrence.weeklyRule(isoWeekdays: weekdays))

        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: [rule]) == weekdays)
    }

    @Test("An event with no recurrence reads as a one-shot")
    func noRulesReadsAsNil() {
        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: nil) == nil)
        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: []) == nil)
    }

    @Test("A pattern this app did not write is never claimed as a match")
    func foreignRulesReadAsNil() {
        // Every-other-week, which the app never writes.
        let fortnightly = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 2,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil
        )
        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: [fortnightly]) == nil)

        // "The first Monday of the month" — a weekly day carrying an ordinal.
        let firstMonday = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1)],
            daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil
        )
        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: [firstMonday]) == nil)

        // A daily repeat carries no days at all.
        let daily = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: [daily]) == nil)
    }

    @Test("An event carrying two rules is not the shape this app writes")
    func multipleRulesReadAsNil() throws {
        let one = try #require(WorkoutCalendarRecurrence.weeklyRule(isoWeekdays: [1]))
        let two = try #require(WorkoutCalendarRecurrence.weeklyRule(isoWeekdays: [3]))

        #expect(WorkoutCalendarRecurrence.isoWeekdays(ofRules: [one, two]) == nil)
    }
}
