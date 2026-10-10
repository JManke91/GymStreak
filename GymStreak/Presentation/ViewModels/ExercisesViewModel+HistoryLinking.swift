//
//  ExercisesViewModel+HistoryLinking.swift
//  GymStreak
//
//  Links name-only workout history to the library (docs/history-import.md §3a).
//

import Foundation

extension ExercisesViewModel {

    /// Links finished-workout rows that carry this exercise's name but no library link — a
    /// history-only import (docs/history-import.md §3a) or pre-`exerciseId` legacy data —
    /// once the name is unique in the library.
    ///
    /// Charts already resolve such rows by name, but PR detection and the AI recaps key by
    /// `WorkoutExercise.stableKey` and have no name fallback: without the link, the first
    /// workout of a new "Bench Press (Barbell)" would be a "PR" against an imported history
    /// it cannot see. An ambiguous name is left alone — which of two exercises the rows
    /// mean is the user's call, via the attribution banner.
    func linkNameOnlyHistory(to exercise: Exercise) {
        guard let legacyHistoryAttribution,
              ExerciseProgressAggregator.isNameUnique(exercise.name, in: exercises)
        else { return }
        let name = exercise.name
        let id = exercise.id
        Task {
            guard let linked = try? await legacyHistoryAttribution.attributeLegacyRows(named: name, to: id),
                  linked > 0
            else { return }
            NotificationCenter.default.post(name: .historySourceDataDidChange, object: nil)
        }
    }
}
