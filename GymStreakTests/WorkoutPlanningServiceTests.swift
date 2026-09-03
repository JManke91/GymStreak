//
//  WorkoutPlanningServiceTests.swift
//  GymStreakTests
//
//  Direct coverage of the cadence occurrence math. It was previously exercised
//  only indirectly, through `RoutinesViewModelTests` and `ScheduleGatingTests`,
//  and calendar sync (docs/calendar-sync.md) makes the calendar a second
//  consumer of exactly these dates — the events the user sees have to agree with
//  the "next sessions" preview in the planning sheet, so the shared helper is
//  pinned here in its own right.
//

import Testing
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutPlanningServiceTests {

    private let calendar = HistoryStatsService.isoGermanCalendar()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        HistoryStatsService.isoGermanCalendar()
            .date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - cadenceAnchor

    @Test("With no completion the reference date is the anchor and counts as a session")
    func anchorFallsBackToTheReferenceDate() {
        let (anchor, countsAsSession) = WorkoutPlanningService.cadenceAnchor(
            startDate: day(2026, 9, 2),
            lastCompleted: nil,
            calendar: calendar
        )

        #expect(anchor == day(2026, 9, 2))
        #expect(countsAsSession)
    }

    @Test("A completion on or after the reference date takes over as the anchor")
    func completionAfterTheReferenceDateReAnchors() {
        let (anchor, countsAsSession) = WorkoutPlanningService.cadenceAnchor(
            startDate: day(2026, 9, 2),
            lastCompleted: day(2026, 9, 5),
            calendar: calendar
        )

        #expect(anchor == day(2026, 9, 5))
        #expect(!countsAsSession)
    }

    @Test("A completion before the reference date is ignored — the fresh start wins")
    func staleCompletionIsIgnored() {
        let (anchor, countsAsSession) = WorkoutPlanningService.cadenceAnchor(
            startDate: day(2026, 9, 2),
            lastCompleted: day(2026, 8, 20),
            calendar: calendar
        )

        #expect(anchor == day(2026, 9, 2))
        #expect(countsAsSession)
    }

    @Test("The anchor is the completion's day, whatever time of day it was")
    func anchorIsNormalizedToTheStartOfTheDay() {
        let afternoon = calendar.date(byAdding: .hour, value: 17, to: day(2026, 9, 5))!
        let (anchor, _) = WorkoutPlanningService.cadenceAnchor(
            startDate: day(2026, 9, 2),
            lastCompleted: afternoon,
            calendar: calendar
        )

        #expect(anchor == day(2026, 9, 5))
    }

    // MARK: - upcomingCadenceDates

    @Test("A never-trained plan starts on its reference date and walks the interval")
    func referenceDateIsTheFirstOccurrence() {
        let dates = WorkoutPlanningService.upcomingCadenceDates(
            startDate: day(2026, 9, 2),
            lastCompleted: nil,
            intervalDays: 5,
            count: 3,
            referenceDate: day(2026, 9, 2)
        )

        #expect(dates == [day(2026, 9, 2), day(2026, 9, 7), day(2026, 9, 12)])
    }

    @Test("After a completion the walk starts one interval later")
    func completionMovesTheSeriesForward() {
        let dates = WorkoutPlanningService.upcomingCadenceDates(
            startDate: day(2026, 9, 1),
            lastCompleted: day(2026, 9, 2),
            intervalDays: 5,
            count: 3,
            referenceDate: day(2026, 9, 2)
        )

        // Trained today, so today is not offered again.
        #expect(dates == [day(2026, 9, 7), day(2026, 9, 12), day(2026, 9, 17)])
    }

    @Test("A far-past anchor fast-forwards onto the grid instead of walking day by day")
    func farPastAnchorFastForwards() {
        // Reference a year back on a 7-day cadence: the grid points are the
        // reference plus multiples of 7, and the first one from today is the
        // only thing that may be offered.
        let dates = WorkoutPlanningService.upcomingCadenceDates(
            startDate: day(2025, 9, 3),
            lastCompleted: nil,
            intervalDays: 7,
            count: 2,
            referenceDate: day(2026, 9, 2)
        )

        #expect(dates == [day(2026, 9, 2), day(2026, 9, 9)])
        for date in dates {
            let offset = calendar.dateComponents([.day], from: day(2025, 9, 3), to: date).day ?? 0
            #expect(offset % 7 == 0)
        }
    }

    @Test("An overdue plan previews from today, not from the days it missed")
    func overduePlanIsForwardLooking() {
        let dates = WorkoutPlanningService.upcomingCadenceDates(
            startDate: day(2026, 8, 1),
            lastCompleted: day(2026, 8, 10),
            intervalDays: 3,
            count: 2,
            referenceDate: day(2026, 9, 2)
        )

        #expect(dates.first! >= day(2026, 9, 2))
        // Still on the grid the plan defines: 10 Aug + k·3.
        let offset = calendar.dateComponents([.day], from: day(2026, 8, 10), to: dates[0]).day ?? 0
        #expect(offset % 3 == 0)
        #expect(dates[1] == calendar.date(byAdding: .day, value: 3, to: dates[0])!)
    }

    @Test("An interval below one is clamped rather than looping forever")
    func nonPositiveIntervalIsClamped() {
        let dates = WorkoutPlanningService.upcomingCadenceDates(
            startDate: day(2026, 9, 2),
            lastCompleted: nil,
            intervalDays: 0,
            count: 3,
            referenceDate: day(2026, 9, 2)
        )

        #expect(dates == [day(2026, 9, 2), day(2026, 9, 3), day(2026, 9, 4)])
    }

    // MARK: - nextDue

    @Test("Next due for a never-trained plan is its reference date")
    func nextDueIsTheReferenceDate() {
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 4, startDate: day(2026, 9, 4))

        let due = WorkoutPlanningService.nextDue(
            for: schedule,
            lastCompleted: nil,
            referenceDate: day(2026, 9, 2)
        )

        #expect(due == day(2026, 9, 4))
    }

    @Test("Next due rolls one interval off the last completion")
    func nextDueRollsOffTheCompletion() {
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 4, startDate: day(2026, 9, 1))

        let due = WorkoutPlanningService.nextDue(
            for: schedule,
            lastCompleted: day(2026, 9, 2),
            referenceDate: day(2026, 9, 2)
        )

        #expect(due == day(2026, 9, 6))
    }

    @Test("An overdue plan's next due is in the past")
    func nextDueGoesOverdue() {
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 3, startDate: day(2026, 8, 1))

        let due = WorkoutPlanningService.nextDue(
            for: schedule,
            lastCompleted: day(2026, 8, 10),
            referenceDate: day(2026, 9, 2)
        )

        #expect(due == day(2026, 8, 13))
    }

    @Test("A paused plan is not due at all")
    func inactivePlanHasNoDueDate() {
        let schedule = RoutineSchedule(type: .everyNDays, intervalDays: 3, startDate: day(2026, 9, 2))
        schedule.isActive = false

        #expect(
            WorkoutPlanningService.nextDue(
                for: schedule,
                lastCompleted: nil,
                referenceDate: day(2026, 9, 2)
            ) == nil
        )
    }
}
