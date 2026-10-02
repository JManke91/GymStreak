//
//  RoutineProgramScheduleTests.swift
//  GymStreakTests
//
//  First due dates from the install sheet's start choice and the program's
//  offsets (docs/routine-programs.md). Pure Domain logic — no actor.
//

import Testing
import Foundation
@testable import GymStreak

struct RoutineProgramScheduleTests {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Sunday 27 Sep 2026, mid-afternoon.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 15, minute: 30))!

    private static func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    private static let routines = RoutineProgramCatalog.beginnerFullBody.routines

    @Test(arguments: [
        (ProgramStartChoice.today, 27),
        (ProgramStartChoice.tomorrow, 28),
        (ProgramStartChoice.day(day(30).addingTimeInterval(9 * 3600)), 30),
    ])
    func firstWorkoutDayIsTheStartOfTheChosenDay(choice: ProgramStartChoice, expectedDay: Int) {
        let first = RoutineProgramSchedule.firstWorkoutDay(for: choice, now: Self.now, calendar: Self.calendar)
        #expect(first == Self.day(expectedDay))
    }

    @Test
    func aPickedDayInThePastClampsToToday() {
        let first = RoutineProgramSchedule.firstWorkoutDay(for: .day(Self.day(20)), now: Self.now, calendar: Self.calendar)
        #expect(first == Self.day(27))
    }

    /// The design's preview: "Full Body A — Today", "Full Body B — Tue 29 Sep".
    @Test
    func fullBodyBStartsTwoDaysAfterA() {
        let starts = RoutineProgramSchedule.firstDueDates(
            for: Self.routines,
            firstWorkoutDay: Self.day(27),
            calendar: Self.calendar
        )
        #expect(starts == [
            ProgramRoutineStart(seedKey: "seed.program.full_body.a", firstDate: Self.day(27)),
            ProgramRoutineStart(seedKey: "seed.program.full_body.b", firstDate: Self.day(29)),
        ])
    }

    /// Restoring only B puts it on the chosen day, not two days after it.
    @Test
    func offsetsAreRelativeToTheEarliestRoutineBeingAdded() {
        let starts = RoutineProgramSchedule.firstDueDates(
            for: [Self.routines[1]],
            firstWorkoutDay: Self.day(28),
            calendar: Self.calendar
        )
        #expect(starts == [ProgramRoutineStart(seedKey: "seed.program.full_body.b", firstDate: Self.day(28))])
    }

    @Test
    func noRoutinesMeansNoDates() {
        #expect(RoutineProgramSchedule.firstDueDates(for: [], firstWorkoutDay: Self.day(27), calendar: Self.calendar).isEmpty)
    }
}
