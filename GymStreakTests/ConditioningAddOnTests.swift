//
//  ConditioningAddOnTests.swift
//  GymStreakTests
//
//  The post-workout conditioning add-on (docs/fight-conditioning.md, ticket 05):
//  the show / easy-now / hard-later decision, the reminder's fire time, and the
//  view model's two actions.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ConditioningAddOnTests {

    let calendar = ProgramTestCalendar.make()
    /// Thursday 24 Sept 2026, 18:00 — the strength workout has just ended.
    let now = ProgramTestCalendar.date(2026, 9, 24, 18)

    /// Week 1 is aerobic-only; week 5 carries both lactic and aerobic targets;
    /// week 9 is alactic. Experienced, non-sparring, so the templates are the
    /// fuller ones.
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

    private func addOn(
        week: ConditioningProgramWeek,
        entries: [ConditioningLogEntry] = [],
        isHeavyLowerBody: Bool = false,
        sparsHard: Bool = false
    ) -> ConditioningAddOnOffer {
        ConditioningProgramCoach.addOn(
            week: week,
            weekEntries: entries,
            recentEntries: entries,
            strengthToday: [StrengthLogEntry(endTime: now, isHeavyLowerBody: isHeavyLowerBody)],
            sparsHard: sparsHard,
            finishedAt: now,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - The decision

    @Test("An open easy session is offered to start now")
    func easySessionStartsNow() {
        guard case .startNow(let target) = addOn(week: aerobicWeek) else {
            Issue.record("expected an easy session to be offered now")
            return
        }
        #expect(target.definition.energySystem == .aerobic)
    }

    @Test("A hard session is offered for later, at least six hours after lifting")
    func hardSessionIsOfferedForLater() {
        // Week 9's easy target filled, so only alactic work is left.
        let entries = [entry(.aerobicBase, hoursAgo: 40)]
        guard case .later(let target, let notBefore) = addOn(week: alacticWeek, entries: entries) else {
            Issue.record("expected the hard session to be deferred")
            return
        }
        #expect(target.definition.energySystem == .alactic)
        #expect(notBefore == now.addingTimeInterval(ConditioningProgramCoach.hardAfterLifting))
    }

    /// The rule that separates the add-on from "today's conditioning": right
    /// after lifting is stricter than the same day as lifting, so an open easy
    /// target wins even in a week whose emphasis is hard work.
    @Test("An open easy target beats the week's hard emphasis right after lifting")
    func easyBeatsHardEmphasisAfterLifting() {
        // Nothing logged in week 5: `suggestion` would pick the lactic target
        // first, because hard work is the week's emphasis and this was not a
        // leg day.
        guard case .session(let suggested, _) = ConditioningProgramCoach.suggestion(
            week: lacticWeek,
            weekEntries: [],
            recentEntries: [],
            strengthToday: [StrengthLogEntry(endTime: now, isHeavyLowerBody: false)],
            sparsHard: false,
            now: now,
            calendar: calendar
        ) else {
            Issue.record("expected today's suggestion to be a session")
            return
        }
        #expect(suggested.isHard)

        guard case .startNow(let offered) = addOn(week: lacticWeek) else {
            Issue.record("expected the add-on to prefer the easy session")
            return
        }
        #expect(!offered.isHard)
    }

    @Test("Nothing is offered when the program says rest")
    func noOfferWhenResting() {
        // Every aerobic target of week 1 already logged this week.
        let entries = aerobicWeek.targets.flatMap { target in
            (0..<target.count).map { entry(target.session, hoursAgo: Double(30 + $0 * 10)) }
        }
        #expect(addOn(week: aerobicWeek, entries: entries) == ConditioningAddOnOffer.none)
    }

    @Test("Nothing is offered once a conditioning session was already logged today")
    func noOfferAfterTrainingToday() {
        #expect(addOn(week: aerobicWeek, entries: [entry(.aerobicBase, hoursAgo: 3)]) == ConditioningAddOnOffer.none)
    }

    @Test("A leg day still offers the open easy session now")
    func legDayOffersEasyNow() {
        guard case .startNow = addOn(week: lacticWeek, isHeavyLowerBody: true) else {
            Issue.record("expected the easy session after a leg day")
            return
        }
    }

    // MARK: - The reminder's fire time

    @Test("A reminder inside waking hours fires exactly at the six-hour mark")
    func reminderKeepsItsTime() {
        let notBefore = ProgramTestCalendar.date(2026, 9, 24, 19, 30)
        #expect(ConditioningProgramCoach.reminderFireDate(notBefore: notBefore, calendar: calendar) == notBefore)
    }

    @Test("A reminder that would land at night moves to the next morning")
    func lateReminderMovesToTheNextMorning() {
        // Lifting ended at 17:00, so six hours later is 23:00 — a notification
        // the user would only read the following morning anyway.
        let notBefore = ProgramTestCalendar.date(2026, 9, 24, 23)
        let fire = ConditioningProgramCoach.reminderFireDate(notBefore: notBefore, calendar: calendar)
        #expect(fire == ProgramTestCalendar.date(2026, 9, 25, ConditioningProgramCoach.reminderEarliestHour))
    }

    @Test("A reminder before the morning hour waits for it, on the same day")
    func earlyReminderWaitsForTheMorning() {
        let notBefore = ProgramTestCalendar.date(2026, 9, 25, 5)
        let fire = ConditioningProgramCoach.reminderFireDate(notBefore: notBefore, calendar: calendar)
        #expect(fire == ProgramTestCalendar.date(2026, 9, 25, ConditioningProgramCoach.reminderEarliestHour))
    }

    @Test("The night push survives a spring-forward DST change as a wall-clock morning")
    func lateReminderAcrossDST() {
        // Europe/Berlin springs forward in the night of 29 March 2026.
        let notBefore = ProgramTestCalendar.date(2026, 3, 28, 23)
        let fire = ConditioningProgramCoach.reminderFireDate(notBefore: notBefore, calendar: calendar)
        #expect(calendar.component(.hour, from: fire) == ConditioningProgramCoach.reminderEarliestHour)
        #expect(calendar.component(.day, from: fire) == 29)
    }

    // MARK: - The view model

    private func makeViewModel(
        enrolled: Bool = true,
        week: Int = 1
    ) throws -> (ConditioningAddOnViewModel, FakeConditioningReminders, ModelContainer) {
        let container = InMemoryModelContainer.make()
        let store = ConditioningProgramStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cloud: NoCloudAddOn(),
            observesExternalChanges: false
        )
        let program = ConditioningProgramViewModel(
            store: store,
            conditioningRecords: SwiftDataConditioningRecordRepository(modelContext: container.mainContext),
            workoutSessions: SwiftDataWorkoutSessionRepository(modelContext: container.mainContext),
            calendar: calendar,
            now: { self.now }
        )
        if enrolled {
            // Enrol so that `week` is the current one and is already three days
            // old — a session logged "earlier this week" has to fall inside it.
            let startDay = now.addingTimeInterval(-Double((week - 1) * 7 + 3) * 86_400)
            program.enroll(startDate: startDay, experience: .experienced, sparsHard: false)
        }
        let reminders = FakeConditioningReminders()
        let viewModel = ConditioningAddOnViewModel(
            program: program,
            safety: StubAddOnSafety(),
            reminders: reminders,
            permission: FakeReminderPermission(),
            makeRun: { plan in
                ConditioningRunViewModel(
                    plan: plan,
                    cues: RecordingConditioningCues(),
                    workoutSaver: RecordingConditioningWorkoutSaver(),
                    healthSync: StubHealthSyncPreference(),
                    records: RecordingConditioningRecordRepository(),
                    // No live timer in a unit test.
                    isTickingAutomatically: false
                )
            },
            calendar: calendar
        )
        return (viewModel, reminders, container)
    }

    @Test("A user who is not enrolled is never offered anything")
    func notEnrolledIsNeverOffered() throws {
        let (viewModel, _, container) = try makeViewModel(enrolled: false)
        _ = container
        viewModel.prepare(finishedAt: now, isHeavyLowerBody: false)
        #expect(viewModel.offer == ConditioningAddOnOffer.none)
    }

    @Test("Dismissing clears the offer in one tap and persists nothing")
    func dismissClearsTheOffer() throws {
        let (viewModel, _, container) = try makeViewModel()
        _ = container
        viewModel.prepare(finishedAt: now, isHeavyLowerBody: false)
        #expect(viewModel.offer != ConditioningAddOnOffer.none)
        viewModel.dismiss()
        #expect(viewModel.offer == ConditioningAddOnOffer.none)
        // The next workout asks again — nothing was written.
        viewModel.prepare(finishedAt: now, isHeavyLowerBody: false)
        #expect(viewModel.offer != ConditioningAddOnOffer.none)
    }

    @Test("Starting the add-on runs the offered session at the program's volume")
    func startRunsTheOfferedSession() throws {
        let (viewModel, reminders, container) = try makeViewModel()
        _ = container
        viewModel.prepare(finishedAt: now, isHeavyLowerBody: false)
        guard case .startNow(let target) = viewModel.offer else {
            Issue.record("expected an easy session to be offered")
            return
        }
        viewModel.start()
        #expect(viewModel.activeRun?.plan.definition.id == target.session)
        #expect(viewModel.activeRun?.plan.options.volume == target.volume)
        // The card is gone, and a stale reminder cannot outlive the session.
        #expect(viewModel.offer == ConditioningAddOnOffer.none)
        #expect(reminders.cancelCount == 1)
    }

    @Test("Remind me later schedules exactly one reminder and confirms its time")
    func remindLaterSchedulesOne() async throws {
        let (viewModel, reminders, container) = try makeViewModel(week: 9)
        _ = container
        // Fill week 9's easy target so only the alactic session is left.
        let plan = ConditioningSessionPlan(
            definition: ConditioningLibrary.aerobicBase,
            options: ConditioningSessionOptions(volume: 30),
            modality: .run
        )
        let start = now.addingTimeInterval(-40 * 3600)
        container.mainContext.insert(ConditioningRecord.make(
            id: UUID(), plan: plan, timeline: ConditioningTimeline(plan: plan), title: "Aerobic base",
            startDate: start, endDate: start.addingTimeInterval(1800), elapsed: 1800, endedEarly: false
        ))

        viewModel.prepare(finishedAt: now, isHeavyLowerBody: false)
        guard case .later(_, let notBefore) = viewModel.offer else {
            Issue.record("expected the hard session to be deferred")
            return
        }
        await viewModel.remindLater()

        #expect(reminders.scheduled.count == 1)
        let expected = ConditioningProgramCoach.reminderFireDate(notBefore: notBefore, calendar: calendar)
        #expect(reminders.scheduled.first?.date == expected)
        #expect(viewModel.remindedAt == expected)
        #expect(!viewModel.isReminderUnavailable)
    }

    @Test("A reminder that cannot be scheduled says so instead of confirming")
    func refusedReminderIsReported() async throws {
        let (viewModel, reminders, container) = try makeViewModel(week: 9)
        reminders.succeeds = false
        let plan = ConditioningSessionPlan(
            definition: ConditioningLibrary.aerobicBase,
            options: ConditioningSessionOptions(volume: 30),
            modality: .run
        )
        let start = now.addingTimeInterval(-40 * 3600)
        container.mainContext.insert(ConditioningRecord.make(
            id: UUID(), plan: plan, timeline: ConditioningTimeline(plan: plan), title: "Aerobic base",
            startDate: start, endDate: start.addingTimeInterval(1800), elapsed: 1800, endedEarly: false
        ))

        viewModel.prepare(finishedAt: now, isHeavyLowerBody: false)
        await viewModel.remindLater()

        #expect(viewModel.remindedAt == nil)
        #expect(viewModel.isReminderUnavailable)
    }
}

// MARK: - Doubles

@MainActor
private final class StubAddOnSafety: ConditioningSafetyAcknowledging {
    var hasAcknowledgedSafety = true
    func recordSafetyAcknowledged() {}
}

private struct NoCloudAddOn: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? { nil }
    func set(_ data: Data, forKey key: String) {}
}

@MainActor
final class FakeConditioningReminders: ConditioningReminderScheduling {
    struct Scheduled: Equatable {
        let title: String
        let body: String
        let date: Date
    }

    var succeeds = true
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelCount = 0

    @discardableResult
    func scheduleConditioningReminder(title: String, body: String, at date: Date) async -> Bool {
        guard succeeds else { return false }
        scheduled.append(Scheduled(title: title, body: body, date: date))
        return true
    }

    func cancelConditioningReminder() { cancelCount += 1 }
}

@MainActor
final class FakeReminderPermission: WorkoutReminderPermissionRequesting {
    var isUndetermined = false
    private(set) var requestCount = 0

    func isReminderPermissionUndetermined() async -> Bool { isUndetermined }

    @discardableResult
    func requestReminderPermission() async -> Bool {
        requestCount += 1
        return true
    }
}
