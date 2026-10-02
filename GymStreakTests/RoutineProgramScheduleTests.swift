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

    // MARK: - Detail timeline

    /// Full Body: A every 4 days from day 0, B every 4 days from day 2 →
    /// A · – · B · – · A … across the 14 days.
    @Test
    func fullBodyTimelineAlternatesAAndBWithARestDayBetween() {
        let days = RoutineProgramSchedule.timeline(
            for: RoutineProgramCatalog.beginnerFullBody,
            from: Self.now,
            dayCount: 14,
            calendar: Self.calendar
        )
        let a = "seed.program.full_body.a", b = "seed.program.full_body.b"
        #expect(days.map(\.routineSeedKey) == [a, nil, b, nil, a, nil, b, nil, a, nil, b, nil, a, nil])
        #expect(days.first?.date == Self.day(27))
        #expect(days.last?.date == Self.calendar.date(byAdding: .day, value: 13, to: Self.day(27)))
    }

    /// Cadence and offsets come from the program, not a hard-coded pattern.
    @Test
    func timelineFollowsTheProgramsCadenceAndOffsets() {
        let routines = Self.routines
        let program = RoutineProgram(
            id: "test",
            cadenceDays: 3,
            routines: [
                RoutineProgramRoutine(seedKey: "x", startOffsetDays: 1, exercises: routines[0].exercises),
                RoutineProgramRoutine(seedKey: "y", startOffsetDays: 2, exercises: routines[1].exercises),
            ],
            alternativeHintKey: nil,
            guidanceRuleKeys: [],
            sourceKeys: []
        )
        let days = RoutineProgramSchedule.timeline(for: program, from: Self.now, dayCount: 6, calendar: Self.calendar)
        #expect(days.map(\.routineSeedKey) == ["x", "y", nil, "x", "y", nil])
    }
}
