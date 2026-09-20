//
//  ConditioningProgram.swift
//  GymStreak
//
//  The vocabulary of the 12-week conditioning program: the enrollment the user
//  makes, the calendar day it is anchored to, and the weekly targets it asks
//  for. Content lives in `ConditioningProgramContent`, week/phase derivation in
//  `ConditioningProgramSchedule`, today's suggestion in `ConditioningProgramCoach`.
//  See docs/fight-conditioning.md.
//

import Foundation

enum ConditioningExperience: String, Codable, CaseIterable, Sendable {
    case beginner, experienced
}

/// A calendar day, stored as its year/month/day rather than as an instant.
///
/// An instant would move with the time zone: a program started "Monday" in Berlin
/// would start on Sunday evening after flying to New York. Year/month/day is the day
/// the user picked wherever they are, and day arithmetic between two such days
/// goes through `Calendar`, which counts a 23- or 25-hour DST day as one day.
struct ConditioningProgramDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Midnight of this day in `calendar`'s time zone.
    func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func adding(days: Int, calendar: Calendar) -> ConditioningProgramDay {
        let date = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return ConditioningProgramDay(date, calendar: calendar)
    }

    /// Whole calendar days from `self` to `other` (negative when `other` is earlier).
    func days(to other: ConditioningProgramDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: startDate(in: calendar), to: other.startDate(in: calendar)).day ?? 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The user's participation in the program. One per user; synced through iCloud
/// key-value storage (`ConditioningProgramStore`).
struct ConditioningProgramEnrollment: Codable, Equatable, Sendable {

    /// A finished pause: the days `from ..< until` did not count.
    struct Pause: Codable, Equatable, Sendable {
        let from: ConditioningProgramDay
        let until: ConditioningProgramDay
    }

    var startDay: ConditioningProgramDay
    var experience: ConditioningExperience
    /// The user spars hard at least twice a week. Hard sparring is counted as a
    /// lactic session, so the program schedules less lactic work.
    var sparsHard: Bool
    var pauses: [Pause]
    /// Set while the program is paused: every day from here on does not count.
    var pausedSince: ConditioningProgramDay?

    init(
        startDay: ConditioningProgramDay,
        experience: ConditioningExperience,
        sparsHard: Bool,
        pauses: [Pause] = [],
        pausedSince: ConditioningProgramDay? = nil
    ) {
        self.startDay = startDay
        self.experience = experience
        self.sparsHard = sparsHard
        self.pauses = pauses
        self.pausedSince = pausedSince
    }

    var isPaused: Bool { pausedSince != nil }
}

/// One of the three blocks: which energy system it emphasizes and its weeks.
struct ConditioningProgramPhase: Identifiable, Equatable, Sendable {
    let system: ConditioningEnergySystem
    let weeks: ClosedRange<Int>
    var id: ConditioningEnergySystem { system }
}

/// "Do this session `count` times this week, at this volume."
struct ConditioningProgramTarget: Identifiable, Equatable, Hashable, Sendable {
    let session: ConditioningSessionDefinition.ID
    let count: Int
    /// One of the session's `volume.options`.
    let volume: Int
    var id: ConditioningSessionDefinition.ID { session }

    var definition: ConditioningSessionDefinition { ConditioningLibrary.session(session) }
    /// Lactic and alactic work — what the spacing rules and the weekly cap are about.
    var isHard: Bool { definition.energySystem != .aerobic }

    var options: ConditioningSessionOptions { ConditioningSessionOptions(volume: volume) }
}

struct ConditioningProgramWeek: Identifiable, Equatable, Sendable {
    /// 1…12.
    let number: Int
    let phase: ConditioningEnergySystem
    /// The final week: reduced volume before whatever the user is peaking for.
    let isTaper: Bool
    let targets: [ConditioningProgramTarget]
    var id: Int { number }
}
