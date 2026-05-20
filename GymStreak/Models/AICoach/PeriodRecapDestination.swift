//
//  PeriodRecapDestination.swift
//  GymStreak
//
//  Navigation destination value for pushing PeriodRecapView
//  onto the HistoryView NavigationStack.
//

import Foundation

/// Hashable value type used with `NavigationLink(value:)` and
/// `.navigationDestination(for: PeriodRecapDestination.self)` in `HistoryView`.
struct PeriodRecapDestination: Hashable {
    let range: PeriodRange
}

// MARK: - PeriodRange Hashable + Identifiable helpers

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
