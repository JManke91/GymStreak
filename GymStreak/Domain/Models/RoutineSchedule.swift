//
//  RoutineSchedule.swift
//  GymStreak
//
//  Per-routine training plan that drives the dynamic weekly goal shown in the
//  Verlauf tab (see docs/workout-planning.md). A routine is either unplanned
//  (no schedule) or planned with one of two modes:
//
//  - `.everyNDays`  — a rolling cadence ("train this every N days"). The weekly
//                     goal counts however many occurrences land in the current
//                     Mon–Sun week, so it varies week to week.
//  - `.weekdays`    — a fixed weekly split (e.g. Mon / Wed / Fri).
//
//  All fields are optional or defaulted so the model stays CloudKit-compatible
//  and requires no store migration. This is iOS-only — the watch never reads
//  schedules (they are not part of the watch-sync DTO).
//

import Foundation
import SwiftData

/// How a routine's occurrences are laid out across time.
enum RoutineScheduleType: String, Codable, CaseIterable {
    case everyNDays
    case weekdays
}

@Model
final class RoutineSchedule {
    var id: UUID = UUID()
    var routine: Routine?

    /// Raw backing for `type` — stored as String for CloudKit compatibility.
    var typeRaw: String = RoutineScheduleType.everyNDays.rawValue

    /// Cadence length in days, used when `type == .everyNDays` (min 1).
    var intervalDays: Int = 3

    /// Bitmask of ISO weekdays (bit `w-1` set ⇒ weekday `w` included, where
    /// 1 = Monday … 7 = Sunday). Used when `type == .weekdays`.
    var weekdaysMask: Int = 0

    /// User-chosen reference date for the `.everyNDays` cadence — a "start
    /// fresh" anchor. Completions *before* this date are ignored; with no
    /// qualifying completion the reference date is the first planned session.
    /// Once a workout lands on or after it, the cadence rolls off that
    /// completion instead (see `WorkoutPlanningService.cadenceAnchor`).
    var startDate: Date = Date()

    /// Allows a plan to be paused without deleting it.
    var isActive: Bool = true

    var createdAt: Date = Date()

    init(
        type: RoutineScheduleType = .everyNDays,
        intervalDays: Int = 3,
        weekdays: Set<Int> = [],
        startDate: Date = Date()
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.intervalDays = intervalDays
        self.weekdaysMask = RoutineSchedule.mask(from: weekdays)
        self.startDate = startDate
        self.isActive = true
        self.createdAt = Date()
    }

    /// Strongly-typed accessor for the schedule mode.
    var type: RoutineScheduleType {
        get { RoutineScheduleType(rawValue: typeRaw) ?? .everyNDays }
        set { typeRaw = newValue.rawValue }
    }

    /// Selected ISO weekdays (1 = Monday … 7 = Sunday).
    var weekdays: Set<Int> {
        get { Set((1...7).filter { weekdaysMask & (1 << ($0 - 1)) != 0 }) }
        set { weekdaysMask = RoutineSchedule.mask(from: newValue) }
    }

    private static func mask(from weekdays: Set<Int>) -> Int {
        weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
    }
}
