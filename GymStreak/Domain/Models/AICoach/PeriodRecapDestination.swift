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

// `PeriodRange`'s `Hashable`/`CaseIterable`/`Identifiable` conformance and its
// `cacheKey` helper live alongside the enum itself in
// `Domain/Models/AICoach/PeriodRange.swift`.
