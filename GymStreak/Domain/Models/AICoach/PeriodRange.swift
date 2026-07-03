//
//  PeriodRange.swift
//  GymStreak
//
//  Describes a discrete calendar period for the AI Coach period recap.
//  Lives in Domain because `PeriodRecapDestination` (a Domain navigation
//  value) depends on it, and `PeriodRecapAggregator` (Data) consumes it —
//  Domain must not depend on Data.
//

import Foundation

/// Describes a discrete calendar period for the AI Coach period recap.
enum PeriodRange {
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case lastThreeMonths
    case thisYear

    /// Returns the `DateInterval` for this period relative to `now`.
    func dateInterval(now: Date = Date()) -> DateInterval {
        let calendar = Calendar.current
        switch self {
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .lastWeek:
            let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            let start = calendar.dateInterval(of: .weekOfYear, for: lastWeek)?.start ?? lastWeek
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? lastWeek
            return DateInterval(start: start, end: end)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return DateInterval(start: start, end: min(end, now))
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let start = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? lastMonth
            return DateInterval(start: start, end: end)
        case .lastThreeMonths:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return DateInterval(start: start, end: now)
        }
    }

    /// Human-readable label for the period in English or German.
    func label(locale: Locale, now: Date = Date()) -> String {
        let isGerman = locale.identifier.hasPrefix("de")
        switch self {
        case .thisWeek:  return isGerman ? "Diese Woche" : "This Week"
        case .lastWeek:  return isGerman ? "Letzte Woche" : "Last Week"
        case .lastThreeMonths: return isGerman ? "Letzten 3 Monate" : "Last 3 Months"
        case .thisYear:  return isGerman ? "Dieses Jahr" : "This Year"
        case .thisMonth, .lastMonth:
            let interval = dateInterval(now: now)
            let fmt = DateFormatter()
            fmt.locale = locale
            fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return fmt.string(from: interval.start)
        }
    }
}

// MARK: - Hashable + Identifiable

extension PeriodRange: Hashable, CaseIterable, Identifiable {

    public static var allCases: [PeriodRange] {
        [.thisWeek, .lastWeek, .thisMonth, .lastMonth, .lastThreeMonths, .thisYear]
    }

    public var id: String { cacheKey }

    /// Stable string key used in cache filenames and equality checks.
    var cacheKey: String {
        switch self {
        case .thisWeek:         return "this_week"
        case .lastWeek:         return "last_week"
        case .thisMonth:        return "this_month"
        case .lastMonth:        return "last_month"
        case .lastThreeMonths:  return "last_3_months"
        case .thisYear:         return "this_year"
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cacheKey)
    }

    public static func == (lhs: PeriodRange, rhs: PeriodRange) -> Bool {
        lhs.cacheKey == rhs.cacheKey
    }
}
