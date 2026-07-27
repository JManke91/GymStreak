//
//  MuscleLoad.swift
//  GymStreak
//

import Foundation

/// What one workout did to one region of the muscle-map figure.
///
/// A plain value type, built once by `MuscleLoadAggregator` from a session's denormalized
/// history: the map renders from these and never traverses SwiftData relationships per belly.
struct MuscleLoad: Hashable, Sendable {
    /// Primary if the region was the leading mover of at least one exercise, secondary otherwise.
    let engagement: MuscleEngagement
    /// Completed sets of the exercises this region led. Supporting work adds nothing here — the
    /// map shows a set count for primary regions and the word "secondary" for the rest.
    let completedSets: Int
    /// Distinct exercise names that hit this region, in the session's exercise order.
    let exerciseNames: [String]
}
