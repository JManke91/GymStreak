//
//  ConditioningProgramCoachTests.swift
//  GymStreakTests
//
//  "Today's conditioning" (docs/fight-conditioning.md): weekly progress and
//  one test per spacing rule, plus the program view model's wiring.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite
struct ConditioningProgramCoachTests {
    let calendar = ProgramTestCalendar.make()
    /// Thursday 24 Sept 2026, 18:00.
    let now = ProgramTestCalendar.date(2026, 9, 24, 18)

    /// Weeks 1 (aerobic) and 5 (lactic) for an experienced, non-sparring user.
    let aerobicWeek = ConditioningProgramContent.week(number: 1, experience: .experienced, sparsHard: false)
    let lacticWeek = ConditioningProgramContent.week(number: 5, experience: .experienced, sparsHard: false)
    let alacticWeek = ConditioningProgramContent.week(number: 9, experience: .experienced, sparsHard: false)

    private func entry(_ id: ConditioningSessionDefinition.ID, hoursAgo: Double) -> ConditioningLogEntry {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return ConditioningLogEntry(
            session: id,
            energySystem: ConditioningLibrary.session(id).energySystem,
            startTime: start,
            endTime: start.addingTimeInterval(40 * 60)
        )
    }

    private func suggestion(
        week: ConditioningProgramWeek,
        entries: [ConditioningLogEntry] = [],
        strength: [StrengthLogEntry] = [],
        sparsHard: Bool = false
    ) -> ConditioningTodaySuggestion {
        ConditioningProgramCoach.suggestion(
            week: week,
            weekEntries: entries,
            recentEntries: entries,
            strengthToday: strength,
            sparsHard: sparsHard,
            now: now,
            calendar: calendar
        )
    }

    private func target(_ id: ConditioningSessionDefinition.ID, in week: ConditioningProgramWeek) -> ConditioningProgramTarget {
        week.targets.first { $0.session == id }!
    }

    // MARK: - Progress

    @Test("Progress counts exact matches first, then fills open targets of the same energy system")
    func progress() {
        let entries = [entry(.lactic45, hoursAgo: 60), entry(.aerobicBase, hoursAgo: 30), entry(.aerobicBase, hoursAgo: 80)]
        let progress = ConditioningProgramCoach.progress(for: lacticWeek, weekEntries: entries)
        #expect(progress.first { $0.target.session == .lactic30 }?.completed == 1)
        #expect(progress.first { $0.target.session == .aerobicBase }?.completed == 1)
    }

    // MARK: - Rules

    @Test("A hard target is suggested first when nothing blocks it")
    func hardFirst() {
        #expect(suggestion(week: lacticWeek) == .session(target(.lactic30, in: lacticWeek), cautions: []))
    }

    @Test("One session a day: anything logged today means rest")
    func oneADay() {
        #expect(suggestion(week: aerobicWeek, entries: [entry(.aerobicBase, hoursAgo: 3)]) == .rest(.alreadyTrainedToday))
    }

    @Test("≥ 48 h between lactic sessions — an easy session is suggested meanwhile")
    func lacticSpacingPrefersEasy() {
        let entries = [entry(.lactic30, hoursAgo: 30)]
        #expect(suggestion(week: lacticWeek, entries: entries) == .session(target(.aerobicBase, in: lacticWeek), cautions: []))
    }

    @Test("≥ 48 h between lactic sessions — with no easy work left the user rests until then")
    func lacticSpacingRest() {
        let lactic = entries(lactic: 30)
        let readyAt = lactic[0].endTime.addingTimeInterval(ConditioningProgramCoach.lacticSpacing)
        #expect(suggestion(week: lacticWeek, entries: lactic) == .rest(.lacticSpacing(until: readyAt)))
    }

    @Test("Lactic is suggested again once 48 h have passed")
    func lacticSpacingElapsed() {
        #expect(suggestion(week: lacticWeek, entries: entries(lactic: 49)) == .session(target(.lactic30, in: lacticWeek), cautions: []))
    }

    @Test("Heavy legs today: easy work is preferred over the hard session")
    func legDayPrefersEasy() {
        let legs = StrengthLogEntry(endTime: now.addingTimeInterval(-3600), isHeavyLowerBody: true)
        #expect(suggestion(week: lacticWeek, strength: [legs]) == .session(target(.aerobicBase, in: lacticWeek), cautions: []))
    }

    @Test("Heavy legs today and only hard work left: flagged ≥ 6 h after the workout")
    func legDayFlagsHard() {
        let legs = StrengthLogEntry(endTime: now.addingTimeInterval(-3600), isHeavyLowerBody: true)
        let aerobicDone = [entry(.aerobicBase, hoursAgo: 50)]
        let expected = ConditioningTodaySuggestion.session(
            target(.alacticPower, in: alacticWeek),
            cautions: [.afterLegWorkout(notBefore: legs.endTime.addingTimeInterval(6 * 3600))]
        )
        #expect(suggestion(week: alacticWeek, entries: aerobicDone, strength: [legs]) == expected)
    }

    @Test("An upper-body day with one leg accessory is not a heavy lower-body workout")
    func heavyLowerBodyThreshold() {
        #expect(!StrengthLogEntry.isHeavyLowerBody(exerciseMuscleGroups: [["Chest"], ["Lats"], ["Quadriceps", "Glutes"]]))
        #expect(StrengthLogEntry.isHeavyLowerBody(exerciseMuscleGroups: [["Quadriceps", "Glutes"], ["Lower Back", "Hamstrings", "Glutes"]]))
    }

    @Test("At most two hard sessions a week")
    func hardCap() {
        // Two alactic sessions done, aerobic open → aerobic; aerobic done too → the week is complete.
        let hard = [entry(.alacticPower, hoursAgo: 30), entry(.alacticPower, hoursAgo: 80)]
        #expect(suggestion(week: alacticWeek, entries: hard) == .session(target(.aerobicBase, in: alacticWeek), cautions: []))

        // Lactic week: two hard sessions of another kind already fill the cap.
        let capped = [entry(.alacticPower, hoursAgo: 60), entry(.alacticPower, hoursAgo: 90), entry(.aerobicBase, hoursAgo: 120)]
        #expect(suggestion(week: lacticWeek, entries: capped) == .rest(.hardSessionCap))
    }

    @Test("A user who spars hard is told to keep hard sessions off sparring days")
    func sparringCaution() {
        let week = ConditioningProgramContent.week(number: 9, experience: .experienced, sparsHard: true)
        #expect(suggestion(week: week, sparsHard: true) == .session(target(.alacticPower, in: week), cautions: [.sparring]))
    }

    @Test("Every target met: the week is complete")
    func weekComplete() {
        let done = [entry(.aerobicBase, hoursAgo: 30), entry(.aerobicBase, hoursAgo: 60), entry(.aerobicBase, hoursAgo: 90), entry(.aerobicBursts, hoursAgo: 110)]
        #expect(suggestion(week: aerobicWeek, entries: done) == .rest(.weekComplete))
    }

    /// Both lactic sessions of week 5 — one of them `hoursAgo` — plus its one aerobic session.
    private func entries(lactic hoursAgo: Double) -> [ConditioningLogEntry] {
        [entry(.lactic30, hoursAgo: hoursAgo), entry(.aerobicBase, hoursAgo: hoursAgo + 20)]
    }
}

@MainActor
@Suite
struct ConditioningProgramViewModelTests {
    let calendar = ProgramTestCalendar.make()

    private func makeViewModel(now: @escaping () -> Date) throws -> (ConditioningProgramViewModel, ModelContainer) {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let store = ConditioningProgramStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cloud: NoCloud(),
            observesExternalChanges: false
        )
        let viewModel = ConditioningProgramViewModel(
            store: store,
            conditioningRecords: SwiftDataConditioningRecordRepository(modelContext: context),
            workoutSessions: SwiftDataWorkoutSessionRepository(modelContext: context),
            calendar: calendar,
            now: now
        )
        return (viewModel, container)
    }

    @Test("Enroll → week 1 with a suggestion; pausing freezes the week; resuming shifts it")
    func pauseAndResume() throws {
        var now = ProgramTestCalendar.date(2026, 9, 21, 9)
        let (viewModel, container) = try makeViewModel(now: { now })
        _ = container

        viewModel.enroll(startDate: now, experience: .beginner, sparsHard: false)
        #expect(viewModel.dashboard?.status == .active(week: 1, dayInWeek: 1, isPaused: false))
        #expect(viewModel.dashboard?.suggestion != nil)
        #expect(viewModel.routinesCard == .enrolled(.active(week: 1, dayInWeek: 1, isPaused: false)))

        now = ProgramTestCalendar.date(2026, 9, 24, 9)
        viewModel.pause()
        now = ProgramTestCalendar.date(2026, 10, 2, 9)
        viewModel.refresh()
        #expect(viewModel.dashboard?.status == .active(week: 1, dayInWeek: 4, isPaused: true))
        #expect(viewModel.dashboard?.suggestion == nil)

        viewModel.resume()
        #expect(viewModel.dashboard?.status == .active(week: 1, dayInWeek: 4, isPaused: false))
        #expect(viewModel.dashboard?.enrollment.pauses.count == 1)
    }

    @Test("A logged session counts toward this week's target")
    func progressFromLoggedSession() throws {
        let now = ProgramTestCalendar.date(2026, 9, 23, 19)
        let (viewModel, container) = try makeViewModel(now: { now })
        viewModel.enroll(startDate: ProgramTestCalendar.date(2026, 9, 21), experience: .beginner, sparsHard: false)

        let plan = ConditioningSessionPlan(
            definition: ConditioningLibrary.aerobicBase,
            options: ConditioningSessionOptions(volume: 30),
            modality: .run
        )
        let start = ProgramTestCalendar.date(2026, 9, 22, 18)
        container.mainContext.insert(ConditioningRecord.make(
            id: UUID(), plan: plan, timeline: ConditioningTimeline(plan: plan), title: "Aerobic base",
            startDate: start, endDate: start.addingTimeInterval(1800), elapsed: 1800, endedEarly: false
        ))
        viewModel.refresh()
        #expect(viewModel.dashboard?.progress.first { $0.target.session == .aerobicBase }?.completed == 1)
    }

    @Test("Leaving clears the dashboard; a dismissed invitation stays hidden")
    func leaveAndDismiss() throws {
        let (viewModel, container) = try makeViewModel(now: { ProgramTestCalendar.date(2026, 9, 21) })
        _ = container
        #expect(viewModel.routinesCard == .invitation)
        viewModel.enroll(startDate: ProgramTestCalendar.date(2026, 9, 21), experience: .beginner, sparsHard: false)
        viewModel.leave()
        #expect(viewModel.dashboard == nil)
        viewModel.dismissRoutinesCard()
        #expect(viewModel.routinesCard == nil)
    }
}

private struct NoCloud: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? { nil }
    func set(_ data: Data, forKey key: String) {}
}
