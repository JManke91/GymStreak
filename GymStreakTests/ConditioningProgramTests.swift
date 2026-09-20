//
//  ConditioningProgramTests.swift
//  GymStreakTests
//
//  The 12-week conditioning program (docs/fight-conditioning.md): week/phase
//  derivation across pauses, DST and time zones; the program content; and the
//  enrollment store's cross-device merge. Spacing rules: ConditioningProgramCoachTests.
//

import Foundation
import Testing
@testable import GymStreak

enum ProgramTestCalendar {
    static func make(_ zone: String = "Europe/Berlin") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, calendar: Calendar = make()) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

@Suite
struct ConditioningProgramScheduleTests {
    let calendar = ProgramTestCalendar.make()
    let start = ConditioningProgramDay(year: 2026, month: 9, day: 21)

    private func enrollment(
        pauses: [ConditioningProgramEnrollment.Pause] = [],
        pausedSince: ConditioningProgramDay? = nil
    ) -> ConditioningProgramEnrollment {
        ConditioningProgramEnrollment(startDay: start, experience: .beginner, sparsHard: false, pauses: pauses, pausedSince: pausedSince)
    }

    private func status(_ offset: Int, _ enrollment: ConditioningProgramEnrollment) -> ConditioningProgramStatus {
        ConditioningProgramSchedule.status(on: start.adding(days: offset, calendar: calendar), enrollment: enrollment, calendar: calendar)
    }

    @Test("Weeks and days count from the start day; day 84 completes the program")
    func weeks() {
        let plain = enrollment()
        #expect(status(-1, plain) == .notStarted(startsOn: start))
        #expect(status(0, plain) == .active(week: 1, dayInWeek: 1, isPaused: false))
        #expect(status(6, plain) == .active(week: 1, dayInWeek: 7, isPaused: false))
        #expect(status(7, plain) == .active(week: 2, dayInWeek: 1, isPaused: false))
        #expect(status(83, plain) == .active(week: 12, dayInWeek: 7, isPaused: false))
        #expect(status(84, plain) == .completed)
    }

    @Test("An open pause freezes the program on the day it began")
    func openPause() {
        let paused = enrollment(pausedSince: start.adding(days: 10, calendar: calendar))
        #expect(status(10, paused) == .active(week: 2, dayInWeek: 4, isPaused: true))
        #expect(status(40, paused) == .active(week: 2, dayInWeek: 4, isPaused: true))
    }

    @Test("A finished pause shifts every later day by its length")
    func closedPause() {
        let pause = ConditioningProgramEnrollment.Pause(
            from: start.adding(days: 10, calendar: calendar),
            until: start.adding(days: 15, calendar: calendar)
        )
        let resumed = enrollment(pauses: [pause])
        #expect(status(15, resumed) == .active(week: 2, dayInWeek: 4, isPaused: false))
        #expect(status(88, resumed) == .active(week: 12, dayInWeek: 7, isPaused: false))
        #expect(status(89, resumed) == .completed)
    }

    @Test("DST changes never shift a week — spring forward and fall back")
    func daylightSaving() {
        // Europe/Berlin: 2026-03-29 has 23 h, 2026-10-25 has 25 h.
        let spring = ConditioningProgramEnrollment(
            startDay: ConditioningProgramDay(year: 2026, month: 3, day: 23), experience: .beginner, sparsHard: false
        )
        let springDay = ConditioningProgramDay(year: 2026, month: 3, day: 30)
        #expect(ConditioningProgramSchedule.status(on: springDay, enrollment: spring, calendar: calendar)
            == .active(week: 2, dayInWeek: 1, isPaused: false))

        let autumn = ConditioningProgramEnrollment(
            startDay: ConditioningProgramDay(year: 2026, month: 10, day: 19), experience: .beginner, sparsHard: false
        )
        let autumnDay = ConditioningProgramDay(year: 2026, month: 10, day: 26)
        #expect(ConditioningProgramSchedule.status(on: autumnDay, enrollment: autumn, calendar: calendar)
            == .active(week: 2, dayInWeek: 1, isPaused: false))
        // Late on the long day itself is still day 7 of week 1.
        let lateOnLongDay = ConditioningProgramDay(ProgramTestCalendar.date(2026, 10, 25, 23, 30), calendar: calendar)
        #expect(ConditioningProgramSchedule.status(on: lateOnLongDay, enrollment: autumn, calendar: calendar)
            == .active(week: 1, dayInWeek: 7, isPaused: false))
    }

    @Test("The start is a calendar day: flying to another time zone keeps the local week")
    func timeZoneTravel() {
        let newYork = ProgramTestCalendar.make("America/New_York")
        let plain = enrollment()
        // Monday 21 Sept, 20:00 in New York is already Tuesday in Berlin; locally it is day 1.
        let mondayEvening = ProgramTestCalendar.date(2026, 9, 21, 20, calendar: newYork)
        let today = ConditioningProgramDay(mondayEvening, calendar: newYork)
        #expect(ConditioningProgramSchedule.status(on: today, enrollment: plain, calendar: newYork)
            == .active(week: 1, dayInWeek: 1, isPaused: false))
    }

    @Test("This week's range starts on the week's first day, spanning a pause inside it")
    func currentWeekStart() {
        let plain = enrollment()
        #expect(ConditioningProgramSchedule.currentWeekStart(on: start.adding(days: 9, calendar: calendar), enrollment: plain, calendar: calendar)
            == start.adding(days: 7, calendar: calendar))
        let pause = ConditioningProgramEnrollment.Pause(
            from: start.adding(days: 8, calendar: calendar),
            until: start.adding(days: 12, calendar: calendar)
        )
        // Day 13 is program day 9 (week 2); week 2 began on calendar day 7.
        #expect(ConditioningProgramSchedule.currentWeekStart(on: start.adding(days: 13, calendar: calendar), enrollment: enrollment(pauses: [pause]), calendar: calendar)
            == start.adding(days: 7, calendar: calendar))
    }
}

@Suite
struct ConditioningProgramContentTests {

    @Test("Twelve weeks: aerobic 1–4, lactic 5–8, alactic 9–12, taper in week 12")
    func phases() {
        let weeks = ConditioningProgramContent.weeks(experience: .experienced, sparsHard: false)
        #expect(weeks.count == 12)
        #expect(weeks.map(\.phase) == Array(repeating: .aerobic, count: 4) + Array(repeating: .lactic, count: 4) + Array(repeating: .alactic, count: 4))
        #expect(weeks.filter(\.isTaper).map(\.number) == [12])
        #expect(weeks[11].targets.map(\.count).reduce(0, +) < weeks[10].targets.map(\.count).reduce(0, +))
    }

    @Test("No week asks for more than two hard sessions, for any user")
    func hardCap() {
        for experience in ConditioningExperience.allCases {
            for spars in [false, true] {
                for week in ConditioningProgramContent.weeks(experience: experience, sparsHard: spars) {
                    let hard = week.targets.filter(\.isHard).map(\.count).reduce(0, +)
                    #expect(hard <= ConditioningProgramCoach.maxHardSessionsPerWeek)
                }
            }
        }
    }

    @Test("Hard sparring counts as lactic: one lactic session from the app instead of two")
    func sparring() {
        let lacticCount = { (spars: Bool) in
            ConditioningProgramContent.week(number: 5, experience: .experienced, sparsHard: spars)
                .targets.filter { $0.definition.energySystem == .lactic }.map(\.count).reduce(0, +)
        }
        #expect(lacticCount(false) == 2)
        #expect(lacticCount(true) == 1)
    }

    @Test("Beginners get the lowest volume; every volume is an option of its session")
    func volumes() {
        for experience in ConditioningExperience.allCases {
            for week in ConditioningProgramContent.weeks(experience: experience, sparsHard: false) {
                for target in week.targets {
                    #expect(target.definition.volume.options.contains(target.volume))
                    if experience == .beginner { #expect(target.volume == target.definition.defaultVolume) }
                }
            }
        }
    }
}

private struct InMemoryProgramCloud: ConditioningProgramCloudStore {
    /// Invariant: written and read only from the `@MainActor` suites below, on one
    /// actor and one thread. The box exists solely so this value-type double can
    /// carry storage that two `ConditioningProgramStore`s share, the way the real
    /// `NSUbiquitousKeyValueStore` is shared between devices.
    final class Box: @unchecked Sendable { var values: [String: Data] = [:] }
    let box = Box()
    func data(forKey key: String) -> Data? { box.values[key] }
    func set(_ data: Data, forKey key: String) { box.values[key] = data }
}

@MainActor
@Suite
struct ConditioningProgramStoreTests {
    let enrollment = ConditioningProgramEnrollment(
        startDay: ConditioningProgramDay(year: 2026, month: 9, day: 21), experience: .experienced, sparsHard: true
    )

    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    @Test("Writes both stores; a fresh install restores the enrollment from iCloud")
    func roundTrip() {
        let cloud = InMemoryProgramCloud()
        let store = ConditioningProgramStore(defaults: defaults(), cloud: cloud, observesExternalChanges: false)
        store.enrollment = enrollment
        let reinstalled = ConditioningProgramStore(defaults: defaults(), cloud: cloud, observesExternalChanges: false)
        #expect(reinstalled.enrollment == enrollment)
    }

    @Test("Leaving on another device is not undone by an older local copy")
    func tombstoneWins() throws {
        let cloud = InMemoryProgramCloud()
        let local = defaults()
        var clock = Date(timeIntervalSince1970: 1_000)
        let thisDevice = ConditioningProgramStore(defaults: local, cloud: cloud, observesExternalChanges: false, now: { clock })
        thisDevice.enrollment = enrollment

        // The other device leaves later and writes the tombstone to iCloud.
        clock = Date(timeIntervalSince1970: 2_000)
        let other = ConditioningProgramStore(defaults: defaults(), cloud: cloud, observesExternalChanges: false, now: { clock })
        other.enrollment = nil

        thisDevice.mergeFromCloud()
        #expect(thisDevice.enrollment == nil)
        let relaunched = ConditioningProgramStore(defaults: local, cloud: cloud, observesExternalChanges: false)
        #expect(relaunched.enrollment == nil)
    }

    @Test("An older iCloud value never overwrites a newer local one")
    func newerLocalKept() {
        let cloud = InMemoryProgramCloud()
        let stale = ConditioningProgramStoredValue(enrollment: nil, updatedAt: Date(timeIntervalSince1970: 1))
        cloud.set(try! JSONEncoder().encode(stale), forKey: ConditioningProgramStore.enrollmentKey)
        let store = ConditioningProgramStore(defaults: defaults(), cloud: InMemoryProgramCloud(), observesExternalChanges: false)
        store.enrollment = enrollment
        #expect(ConditioningProgramStoredValue.newer(store.storedValue, stale)?.enrollment == enrollment)
    }
}
