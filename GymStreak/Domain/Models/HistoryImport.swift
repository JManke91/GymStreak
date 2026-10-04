//
//  HistoryImport.swift
//  GymStreak
//
//  Value types of the workout-history import (docs/history-import.md). Everything
//  here is `Sendable` because it crosses from the parsing/model-actor side to the
//  `@MainActor` view model and back.
//

import Foundation

/// One set as it appeared in the file, in the **file's** weight unit — conversion to
/// the canonical kilograms happens only when it is written (`HistoryImportMatching`).
struct ImportedSet: Sendable, Equatable {
    let weight: Double
    let reps: Int
}

/// One exercise block of an imported workout, in file order.
struct ImportedExercise: Sendable, Equatable {
    let name: String
    var sets: [ImportedSet]
}

/// One workout of the file. Becomes one routine-less `WorkoutSession`.
struct ImportedWorkout: Sendable, Equatable {
    let name: String
    let startTime: Date
    let duration: TimeInterval
    var notes: String
    var exercises: [ImportedExercise]
}

/// The whole file, parsed and validated, nothing written yet.
struct ParsedHistoryFile: Sendable, Equatable {
    let workouts: [ImportedWorkout]
    /// Rows with distance or time but no weight and no reps. History has no cardio
    /// fields, so they are skipped and reported rather than imported as empty sets.
    let skippedCardioSetCount: Int
    /// The unit the header names, when it names one (newer Strong exports write
    /// `Weight (kg)` / `Weight (lbs)`). Only preselects the unit picker — the user decides.
    let detectedWeightUnit: WeightUnit?
}

/// What the user confirms before anything is written.
struct HistoryImportPreview: Sendable {
    let file: ParsedHistoryFile
    let earliest: Date
    let latest: Date
    /// Workouts whose start time and name already exist in history — skipped on import.
    let alreadyImportedCount: Int
    /// Distinct exercise names that resolve to an existing library exercise.
    let matchedExerciseCount: Int
    /// Distinct exercise names that will be created as custom exercises, sorted.
    let newExerciseNames: [String]

    var workoutCount: Int { file.workouts.count }
}

/// The summary shown once the import finished.
struct HistoryImportResult: Sendable, Equatable {
    let importedWorkoutCount: Int
    let skippedDuplicateCount: Int
    let createdExerciseCount: Int
    let skippedCardioSetCount: Int
}

enum HistoryImportError: Error, Equatable {
    /// The file could not be read or is not UTF-8 text.
    case unreadableFile
    /// The header lacks the columns of a Strong workout export.
    case notAStrongExport
    /// A data row could not be parsed (1-based line number in the file).
    case malformedRow(line: Int)
    /// The file parsed, but contains no strength set to import.
    case noWorkouts
    /// Saving failed part-way. Saved chunks stay; re-importing finishes the rest.
    case writeFailed
}
