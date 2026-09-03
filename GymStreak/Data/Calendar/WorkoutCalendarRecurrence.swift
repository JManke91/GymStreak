//
//  WorkoutCalendarRecurrence.swift
//  GymStreak
//
//  The one place ISO weekday numbering meets EventKit's, in both directions:
//  building the weekly `EKRecurrenceRule` a fixed-weekday plan becomes, and
//  reading the pattern back off an event so the reconciler can tell an unchanged
//  series from an edited one.
//  See docs/calendar-sync.md §13b.
//

import EventKit
import Foundation

/// Translates a fixed-weekday plan to and from a weekly `EKRecurrenceRule`.
///
/// **The two numberings are not the same and never line up.** `RoutineSchedule`
/// and `WorkoutPlanningService` speak ISO — 1 = Monday … 7 = Sunday — while
/// `EKWeekday` is Gregorian, 1 = Sunday … 7 = Saturday. `EKWeekday(rawValue:)`
/// applied to an ISO weekday is wrong for all seven days, not just the boundary,
/// so the mapping is written out case by case rather than as arithmetic that
/// reads plausibly and is off by one.
enum WorkoutCalendarRecurrence {

    /// The open-ended weekly rule for a set of ISO weekdays, or `nil` when the
    /// set is empty (which is not a plan).
    ///
    /// `end: nil` is the whole point: the occurrences keep coming, so a user who
    /// does not open the app for two months still has a populated calendar.
    static func weeklyRule(isoWeekdays: Set<Int>) -> EKRecurrenceRule? {
        let days = isoWeekdays.sorted().compactMap(ekWeekday(fromISO:))
        guard !days.isEmpty else { return nil }
        return EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: days.map { EKRecurrenceDayOfWeek($0) },
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }

    /// The ISO weekdays an event actually repeats on, or `nil` when it is not a
    /// plain weekly series of the shape this app writes.
    ///
    /// Anything else — a monthly rule, an interval of two weeks, a rule the user
    /// edited in Calendar.app — reads as "not the pattern the plan asks for", so
    /// the reconciler rewrites it rather than trusting a shape it did not create.
    ///
    /// Takes the rules rather than the `EKEvent` they came off, so the mapping
    /// can be tested without constructing an `EKEventStore` — an `EKEvent` needs
    /// one, an `EKRecurrenceRule` does not.
    static func isoWeekdays(ofRules rules: [EKRecurrenceRule]?) -> Set<Int>? {
        guard let rules, rules.count == 1,
              let rule = rules.first,
              rule.frequency == .weekly,
              rule.interval == 1,
              let days = rule.daysOfTheWeek, !days.isEmpty else { return nil }
        // `weekNumber` is meaningful only for monthly and yearly rules; a weekly
        // one that carries a non-zero week ordinal is not something this app
        // wrote, so it is not claimed as a match either.
        guard days.allSatisfy({ $0.weekNumber == 0 }) else { return nil }
        return Set(days.map { isoWeekday(from: $0.dayOfTheWeek) })
    }

    // MARK: - The numbering boundary

    /// ISO 1 = Monday … 7 = Sunday → `EKWeekday`, whose 1 is Sunday.
    static func ekWeekday(fromISO isoWeekday: Int) -> EKWeekday? {
        switch isoWeekday {
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        case 6: return .saturday
        case 7: return .sunday
        default: return nil
        }
    }

    /// `EKWeekday` → ISO 1 = Monday … 7 = Sunday.
    static func isoWeekday(from ekWeekday: EKWeekday) -> Int {
        switch ekWeekday {
        case .monday: return 1
        case .tuesday: return 2
        case .wednesday: return 3
        case .thursday: return 4
        case .friday: return 5
        case .saturday: return 6
        case .sunday: return 7
        @unknown default: return 1
        }
    }
}
