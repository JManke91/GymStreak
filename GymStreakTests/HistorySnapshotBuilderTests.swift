//
//  HistorySnapshotBuilderTests.swift
//  GymStreakTests
//
//  Guards the History screen's precomputation refactor (docs/history-performance.md):
//  the single-pass `WorkoutSession.aggregates` that replaced four separate relationship
//  traversals, and the flattened row list that replaced a nested lazy stack.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct HistorySnapshotBuilderTests {

    // MARK: - Single-pass aggregates

    /// The volume formula moved out of `totalVolume` into `aggregates`. This pins the numbers
    /// against hand-computed values so the move cannot have changed the arithmetic.
    @Test
    func aggregatesCountSetsAndVolumeInOnePass() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        // 3 completed sets (2 + 1) and 1 incomplete.
        addExercise(to: session, order: 0, sets: [(weight: 100, reps: 5, done: true),
                                                  (weight: 100, reps: 5, done: true),
                                                  (weight: 100, reps: 5, done: false)], context: context)
        addExercise(to: session, order: 1, sets: [(weight: 50, reps: 10, done: true)], context: context)
        try context.save()

        let totals = session.aggregates

        #expect(totals.completedSets == 3)
        #expect(totals.totalSets == 4)
        let expectedVolume: Double = (100 * 5) + (100 * 5) + (50 * 10)   // incomplete set excluded
        #expect(totals.volume == expectedVolume)
        #expect(totals.completionPercentage == 75)
    }

    /// The individual properties now delegate to `aggregates`; they must still agree with it, since
    /// other screens read them directly.
    @Test
    func derivedPropertiesAgreeWithAggregates() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        addExercise(to: session, order: 0, sets: [(weight: 80, reps: 8, done: true),
                                                  (weight: 80, reps: 6, done: true)], context: context)
        try context.save()

        let totals = session.aggregates
        #expect(session.totalVolume == totals.volume)
        #expect(session.completionPercentage == totals.completionPercentage)
        #expect(session.completedSetsCount == totals.completedSets)
        #expect(session.totalSetsCount == totals.totalSets)
    }

    @Test
    func aggregatesOfEmptySessionAreZeroAndDoNotDivideByZero() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        try context.save()

        let totals = session.aggregates
        #expect(totals.completedSets == 0)
        #expect(totals.totalSets == 0)
        #expect(totals.volume == 0)
        #expect(totals.completionPercentage == 0)
    }

    // MARK: - Row flattening

    /// Rows are a single flat sequence: cards for the newest month first, then a divider before
    /// each *subsequent* month. The first month deliberately has no divider.
    @Test
    func rowsInterleaveMonthDividersWithoutOneAboveTheFirstMonth() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()

        let july = try makeFinishedSession(year: 2026, month: 7, day: 20, context: context, calendar: calendar)
        let julyEarlier = try makeFinishedSession(year: 2026, month: 7, day: 4, context: context, calendar: calendar)
        let june = try makeFinishedSession(year: 2026, month: 6, day: 11, context: context, calendar: calendar)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [july, julyEarlier, june],    // newest first, as the repository returns them
            routines: [],
            prCountBySession: [:],
            referenceDate: try date(2026, 7, 26, calendar: calendar)
        )

        let kinds = snapshot.rows.map { row -> String in
            switch row {
            case .monthHeader: return "header"
            case .card:        return "card"
            }
        }
        #expect(kinds == ["card", "card", "header", "card"])
        #expect(snapshot.sessionCount == 3)

        // Cards keep the incoming newest-first order.
        let cardIds = snapshot.rows.compactMap { row -> UUID? in
            if case .card(let card) = row { return card.id }
            return nil
        }
        #expect(cardIds == [july.id, julyEarlier.id, june.id])
    }

    @Test
    func rowIdentitiesAreStableAndUnique() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()
        let sessions = try [
            makeFinishedSession(year: 2026, month: 7, day: 20, context: context, calendar: calendar),
            makeFinishedSession(year: 2026, month: 6, day: 11, context: context, calendar: calendar),
            makeFinishedSession(year: 2026, month: 5, day: 2, context: context, calendar: calendar)
        ]
        try context.save()

        let build = { HistorySnapshotBuilder.build(sessions: sessions, routines: [], prCountBySession: [:]) }
        let first = build().rows.map(\.id)
        let second = build().rows.map(\.id)

        #expect(first == second, "ids must not change between builds or lazy rows rebuild needlessly")
        #expect(Set(first).count == first.count, "ids must be unique")
    }

    @Test
    func emptyHistoryProducesNoRows() {
        let snapshot = HistorySnapshotBuilder.build(sessions: [], routines: [], prCountBySession: [:])
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.sessionCount == 0)
        #expect(snapshot.cardsByDay.isEmpty)
    }

    // MARK: - Card contents

    @Test
    func cardCarriesPRCountAndAggregates() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        session.endTime = session.startTime.addingTimeInterval(1_800)   // 30 min
        addExercise(to: session, order: 0, sets: [(weight: 60, reps: 10, done: true)], context: context)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [session],
            routines: [],
            prCountBySession: [session.id: 2]
        )

        guard case .card(let card) = try #require(snapshot.rows.first) else {
            Issue.record("expected a card row"); return
        }
        #expect(card.prLifts == 2)
        #expect(card.isPR)
        #expect(card.completedSets == 1)
        #expect(card.totalVolume == 600)
        #expect(card.durationMinutes == 30)
    }

    /// Two finished workouts on one day: the calendar shows the later one.
    @Test
    func cardsByDayPrefersTheLaterWorkout() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()

        let morning = try makeFinishedSession(year: 2026, month: 7, day: 20, hour: 8, context: context, calendar: calendar)
        let evening = try makeFinishedSession(year: 2026, month: 7, day: 20, hour: 19, context: context, calendar: calendar)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [evening, morning],
            routines: [],
            prCountBySession: [:]
        )

        let day = calendar.startOfDay(for: evening.startTime)
        #expect(snapshot.cardsByDay[day]?.id == evening.id)
        #expect(snapshot.cardsByDay.count == 1)
    }

    // MARK: - Input normalisation

    /// Month order and in-month card order depend on newest-first input, and every count depends on
    /// unfinished sessions being excluded. The builder enforces both rather than trusting callers.
    @Test
    func builderNormalisesUnsortedInputAndDropsUnfinishedSessions() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let calendar = HistoryStatsService.isoGermanCalendar()

        let june = try makeFinishedSession(year: 2026, month: 6, day: 11, context: context, calendar: calendar)
        let julyLate = try makeFinishedSession(year: 2026, month: 7, day: 25, context: context, calendar: calendar)
        let julyEarly = try makeFinishedSession(year: 2026, month: 7, day: 2, context: context, calendar: calendar)
        let inProgress = try makeFinishedSession(year: 2026, month: 7, day: 26, context: context, calendar: calendar)
        inProgress.endTime = nil
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [june, inProgress, julyEarly, julyLate],   // deliberately unsorted
            routines: [],
            prCountBySession: [:]
        )

        #expect(snapshot.sessionCount == 3, "the unfinished session is excluded")
        let cardIds = snapshot.rows.compactMap { row -> UUID? in
            if case .card(let card) = row { return card.id }
            return nil
        }
        #expect(cardIds == [julyLate.id, julyEarly.id, june.id], "sorted newest-first, July before June")
        #expect(snapshot.cardsByDay.count == 3)
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, calendar: Calendar) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(calendar.date(from: components))
    }

    private func makeSession(context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.routineName = "Push"
        session.endTime = session.startTime.addingTimeInterval(3_600)
        context.insert(session)
        return session
    }

    private func makeFinishedSession(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        context: ModelContext,
        calendar: Calendar
    ) throws -> WorkoutSession {
        let session = makeSession(context: context)
        session.startTime = try date(year, month, day, hour: hour, calendar: calendar)
        session.endTime = session.startTime.addingTimeInterval(3_600)
        return session
    }

    @discardableResult
    private func addExercise(
        to session: WorkoutSession,
        order: Int,
        sets: [(weight: Double, reps: Int, done: Bool)],
        context: ModelContext
    ) -> WorkoutExercise {
        let workoutExercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["chest"],
            order: order,
            exerciseId: UUID()
        )
        workoutExercise.workoutSession = session
        context.insert(workoutExercise)

        for (index, spec) in sets.enumerated() {
            let set = WorkoutSet(
                plannedReps: spec.reps,
                actualReps: spec.reps,
                plannedWeight: spec.weight,
                actualWeight: spec.weight,
                restTime: 60,
                order: index
            )
            set.isCompleted = spec.done
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
        return workoutExercise
    }
}
