//
//  MatSessionHistoryTests.swift
//  GymStreakTests
//
//  Logged mat sessions in History (docs/fight-conditioning.md, "Mat sessions"): the
//  merge with workouts and conditioning — and that neither the conditioning program
//  nor the strength statistics see them.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct MatSessionHistoryTests {

    // MARK: - History

    @Test
    func matSessionsInterleaveWithWorkoutsAndConditioningByDate() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let workout = try makeWorkout(day: 10, hour: 8, context: context)
        let conditioning = try makeConditioning(day: 10, hour: 20, context: context)
        let mat = try makeMat(day: 10, hour: 13, context: context)
        let laterMat = try makeMat(day: 11, hour: 9, context: context)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [workout],
            routines: [],
            prCountBySession: [:],
            conditioningRecords: [conditioning],
            matSessions: [mat, laterMat]
        )

        #expect(snapshot.rows.map(\.id) == [
            "mat-\(laterMat.id.uuidString)",
            "conditioning-\(conditioning.id.uuidString)",
            "mat-\(mat.id.uuidString)",
            "card-\(workout.id.uuidString)"
        ])
        #expect(snapshot.matSessionCount == 2)
    }

    @Test
    func aMonthWithOnlyMatSessionsGetsItsDivider() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let september = try makeWorkout(day: 12, hour: 12, context: context)
        let august = try makeMat(month: 8, day: 3, hour: 18, context: context)
        try context.save()

        let snapshot = HistorySnapshotBuilder.build(
            sessions: [september],
            routines: [],
            prCountBySession: [:],
            matSessions: [august]
        )

        #expect(snapshot.rows.map(\.id) == [
            "card-\(september.id.uuidString)",
            "month-2026-8",
            "mat-\(august.id.uuidString)"
        ])
        let augustSection = try #require(snapshot.monthTotals["2026-8"])
        #expect(augustSection.matSessionCount == 1)
        #expect(augustSection.sessionCount == 0)
        #expect(augustSection.totalVolume == 0)
    }

    /// Strength statistics — the week hero, the calendar, the session count that gates the
    /// AI Coach recap, last month's volume and PRs — are identical with or without mat sessions.
    @Test
    func matSessionsLeaveStrengthStatisticsUnchanged() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let reference = try date(month: 9, day: 15, hour: 12)
        let workout = try makeWorkout(day: 14, hour: 9, context: context)
        let mat = try makeMat(day: 14, hour: 19, context: context)
        let lastMonthMat = try makeMat(month: 8, day: 20, hour: 19, context: context)
        try context.save()

        let without = HistorySnapshotBuilder.build(
            sessions: [workout], routines: [], prCountBySession: [:], referenceDate: reference
        )
        let with = HistorySnapshotBuilder.build(
            sessions: [workout], routines: [], prCountBySession: [:],
            matSessions: [mat, lastMonthMat], referenceDate: reference
        )

        #expect(with.weekStats.completedCount == without.weekStats.completedCount)
        #expect(with.weekStats.weekVolume == without.weekStats.weekVolume)
        #expect(with.weekStats.prCount == without.weekStats.prCount)
        #expect(with.weekStats.streakWeeks == without.weekStats.streakWeeks)
        #expect(with.weekDays.map(\.hasWorkout) == without.weekDays.map(\.hasWorkout))
        #expect(with.cardsByDay == without.cardsByDay)
        #expect(with.sessionCount == without.sessionCount)
        #expect(with.lastMonth.count == without.lastMonth.count)
        #expect(with.lastMonth.volumeTons == without.lastMonth.volumeTons)
        #expect(with.lastMonth.prs == without.lastMonth.prs)
        #expect(with.conditioningCount == 0)
    }

    // MARK: - Conditioning program

    /// Sparring is not the energy-system work the program prescribes: a mat session in the
    /// current week moves neither the weekly targets nor today's suggestion.
    @Test
    func matSessionsDoNotCountTowardTheProgramWeek() throws {
        let calendar = ProgramTestCalendar.make()
        let now = ProgramTestCalendar.date(2026, 9, 24, 18)
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let program = ConditioningProgramViewModel(
            store: ConditioningProgramStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!,
                cloud: NoProgramCloud(),
                observesExternalChanges: false
            ),
            conditioningRecords: SwiftDataConditioningRecordRepository(modelContext: context),
            workoutSessions: SwiftDataWorkoutSessionRepository(modelContext: context),
            calendar: calendar,
            now: { now }
        )
        program.enroll(startDate: ProgramTestCalendar.date(2026, 9, 21, 9), experience: .beginner, sparsHard: false)
        let before = try #require(program.dashboard)

        for hoursAgo in [2.0, 26, 50] {
            context.insert(MatSession(
                startTime: now.addingTimeInterval(-hoursAgo * 3_600),
                endTime: now.addingTimeInterval(-hoursAgo * 3_600 + 5_400),
                sport: .bjj,
                intensity: .hardSparring
            ))
        }
        try context.save()
        program.refresh()

        let after = try #require(program.dashboard)
        #expect(after.progress == before.progress)
        #expect(after.progress.allSatisfy { $0.completed == 0 })
        #expect(after.suggestion == before.suggestion)
    }

    // MARK: - Helpers

    private let calendar = HistoryStatsService.isoGermanCalendar()

    private func date(month: Int = 9, day: Int, hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    private func makeWorkout(day: Int, hour: Int, context: ModelContext) throws -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.routineName = "Push"
        session.startTime = try date(day: day, hour: hour)
        session.endTime = session.startTime.addingTimeInterval(3_600)
        context.insert(session)
        return session
    }

    private func makeConditioning(day: Int, hour: Int, context: ModelContext) throws -> ConditioningRecord {
        let start = try date(day: day, hour: hour)
        let record = ConditioningRecord(
            id: UUID(),
            startTime: start,
            endTime: start.addingTimeInterval(1_200),
            sessionTypeRaw: ConditioningSessionDefinition.ID.lactic30.rawValue,
            titleSnapshot: "Lactic 30/120",
            energySystemRaw: ConditioningEnergySystem.lactic.rawValue,
            modalityRaw: ConditioningModality.rower.rawValue,
            effortRaw: ConditioningEffort.hardRepeatable.rawValue,
            roundsCompleted: 6,
            roundsPlanned: 6,
            setsPlanned: 0,
            workInterval: 30,
            restInterval: 120,
            endedEarly: false
        )
        context.insert(record)
        return record
    }

    private func makeMat(month: Int = 9, day: Int, hour: Int, context: ModelContext) throws -> MatSession {
        let start = try date(month: month, day: day, hour: hour)
        let session = MatSession(
            startTime: start,
            endTime: start.addingTimeInterval(5_400),
            sport: .bjj,
            intensity: .moderate
        )
        context.insert(session)
        return session
    }
}

private struct NoProgramCloud: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? { nil }
    func set(_ data: Data, forKey key: String) {}
}
