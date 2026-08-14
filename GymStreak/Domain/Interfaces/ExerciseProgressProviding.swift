//
//  ExerciseProgressProviding.swift
//  GymStreak
//
//  Protocol surface for exercise-vs-previous comparison, extracted so
//  Presentation-layer Views/ViewModels can depend on an abstraction rather
//  than the `ExerciseProgressService` concrete Data-layer type directly.
//

import Foundation

/// "How did this workout compare with last time?" for the save sheet, the workout detail
/// screen and the AI Coach's workout analysis.
///
/// `@MainActor` and `async` (audit P1.6). The isolation is not the old one: the history
/// scan behind this now runs inside `SwiftDataHistorySnapshotStore`'s model actor, and
/// what stays on the main actor is only the bounded read of the workout the caller
/// already holds. Conformers must keep it that way — a `@MainActor` implementation that
/// fetches history itself would restore the hang this replaced.
///
/// The exercise **chart** deliberately does not come through here; it reads
/// `HistorySnapshotProviding` directly (audit P1.2).
@MainActor
protocol ExerciseProgressProviding {

    /// Compares every exercise of `workout` with its previous performance, in `order`.
    ///
    /// - Returns: one row per exercise, or an **empty array** if the history lookup
    ///   failed. Empty is deliberate: returning rows with no predecessor would badge
    ///   every exercise "new", which is a wrong answer rather than a missing one.
    func compareWithPrevious(workout: WorkoutSession) async -> [ExerciseComparisonResult]
}
