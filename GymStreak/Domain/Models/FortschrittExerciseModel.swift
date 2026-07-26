//
//  FortschrittExerciseModel.swift
//  GymStreak
//

import Foundation

/// Immutable row values for the Fortschritt tab.
///
/// This lives in Domain because the Data-layer history actor produces it and Presentation consumes
/// it. It is an aggregate, not a DTO mirror of the SwiftData store.
struct FortschrittExerciseModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let primaryMuscleGroup: String
    let muscleGroups: [String]
    let exerciseId: UUID?
    let workoutCount: Int
    let lastPerformed: Date?
    let trendPct: Double?
    let sparkline: [Double]
}
