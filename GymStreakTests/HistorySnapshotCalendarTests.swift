//
//  HistorySnapshotCalendarTests.swift
//  GymStreakTests
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct HistorySnapshotCalendarTests {
    @Test
    func monthTotalsCountEverySessionEvenWhenTwoShareADay() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()

        let morning = try makeSession(
            year: 2026, month: 7, day: 20, hour: 8, context: context, calendar: calendar
        )
        addExercise(to: morning, weight: 100, reps: 5, context: context)
        let evening = try makeSession(
            year: 2026, month: 7, day: 20, hour: 19, context: context, calendar: calendar
        )
        addExercise(to: evening, weight: 50, reps: 4, context: context)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [evening, morning],
            routines: [],
            prCountBySession: [:]
        )
        let id = MonthSectionModel.id(year: 2026, month: 7)
        let totals = try #require(snapshot.monthTotals[id])
        #expect(totals.sessionCount == 2)
        #expect(totals.totalVolume == 700)
        #expect(snapshot.cardsByDay.count == 1)
    }

    @Test
    func dividerTotalsMatchMonthTotals() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()

        let july = try makeSession(
            year: 2026, month: 7, day: 20, context: context, calendar: calendar
        )
        addExercise(to: july, weight: 90, reps: 5, context: context)
        let june1 = try makeSession(
            year: 2026, month: 6, day: 11, context: context, calendar: calendar
        )
        addExercise(to: june1, weight: 80, reps: 5, context: context)
        let june2 = try makeSession(
            year: 2026, month: 6, day: 3, context: context, calendar: calendar
        )
        addExercise(to: june2, weight: 70, reps: 5, context: context)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [july, june1, june2],
            routines: [],
            prCountBySession: [:]
        )

        for row in snapshot.rows {
            guard case .monthHeader(let divider) = row else { continue }
            let totals = try #require(snapshot.monthTotals[divider.id])
            #expect(divider.sessionCount == totals.sessionCount)
            #expect(divider.totalVolume == totals.totalVolume)
        }
    }

    @Test
    func typesByMonthIncludesEverySameDayWorkout() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()

        let pull = try makeSession(
            year: 2026, month: 7, day: 20, hour: 8, context: context, calendar: calendar
        )
        pull.routineName = "Pull Day"
        let legs = try makeSession(
            year: 2026, month: 7, day: 20, hour: 19, context: context, calendar: calendar
        )
        legs.routineName = "Leg Day"
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [legs, pull],
            routines: [],
            prCountBySession: [:]
        )
        let id = MonthSectionModel.id(year: 2026, month: 7)
        #expect(try #require(snapshot.typesByMonth[id]).count == 2)
    }

    private func makeSession(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        context: ModelContext,
        calendar: Calendar
    ) throws -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.routineName = "Push"
        session.startTime = try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
        session.endTime = session.startTime.addingTimeInterval(3_600)
        context.insert(session)
        return session
    }

    private func addExercise(
        to session: WorkoutSession,
        weight: Double,
        reps: Int,
        context: ModelContext
    ) {
        let exercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["chest"],
            order: 0,
            exerciseId: UUID()
        )
        exercise.workoutSession = session
        context.insert(exercise)

        let set = WorkoutSet(
            plannedReps: reps,
            actualReps: reps,
            plannedWeight: weight,
            actualWeight: weight,
            restTime: 60,
            order: 0
        )
        set.isCompleted = true
        set.workoutExercise = exercise
        context.insert(set)
    }
}
