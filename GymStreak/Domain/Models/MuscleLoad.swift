//
//  MuscleLoad.swift
//  GymStreak
//

import Foundation

/// What one reading of the app's data does to one region of the muscle-map figure.
///
/// A plain value type, built once by `MuscleLoadAggregator`: the map renders from these and
/// never traverses SwiftData relationships per belly. It is deliberately neutral about *which*
/// reading produced it — a recorded workout contributes completed sets, a routine contributes
/// planned ones, and the card renders both the same way.
struct MuscleLoad: Hashable, Sendable {
    /// Primary if the region was the leading mover of at least one exercise, secondary otherwise.
    let engagement: MuscleEngagement
    /// Sets of the exercises this region led — completed ones for a workout, planned ones for a
    /// routine. Supporting work adds nothing here: the map shows a set count for primary regions
    /// and the word "secondary" for the rest.
    let setCount: Int
    /// Distinct exercise names that hit this region, in the source's exercise order.
    let exerciseNames: [String]
}
