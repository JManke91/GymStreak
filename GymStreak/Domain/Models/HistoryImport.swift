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
    /// Start time of the workout of each row with distance or time but no weight and no
    /// reps. History has no cardio fields, so they are skipped and reported rather than
    /// imported as empty sets; dated so a period filter counts only its own.
    let skippedCardioSetStartTimes: [Date]
    /// The unit the header names, when it names one (newer Strong exports write
    /// `Weight (kg)` / `Weight (lbs)`). Only preselects the unit picker — the user decides.
    let detectedWeightUnit: WeightUnit?

    var skippedCardioSetCount: Int { skippedCardioSetStartTimes.count }

    /// The workouts (and cardio skips) starting inside `range`; nil keeps everything.
    func restricted(to range: ClosedRange<Date>?) -> ParsedHistoryFile {
        guard let range else { return self }
        return ParsedHistoryFile(
            workouts: workouts.filter { range.contains($0.startTime) },
            skippedCardioSetStartTimes: skippedCardioSetStartTimes.filter { range.contains($0) },
            detectedWeightUnit: detectedWeightUnit
        )
    }
}

/// What the user confirms before anything is written.
///
/// Holds the store's answers as lookups rather than counts, so a period filter can be
/// re-summarised on the main actor without another round trip (`summary(in:)`).
struct HistoryImportPreview: Sendable {
    let file: ParsedHistoryFile
    let earliest: Date
    let latest: Date
    /// `HistoryImportMatching.dedupeKey`s of the file's workouts already in history.
    let alreadyImportedKeys: Set<String>
    /// Normalized exercise names of the file that resolve to a library exercise.
    let libraryMatchedNames: Set<String>

    /// The counts for the workouts starting inside `range` (nil: the whole file).
    ///
    /// Exercise counts cover only the workouts that will actually be written — the store
    /// resolves exercises for pending workouts only, so a name that appears solely in
    /// already-imported workouts is never created and must not be promised.
    func summary(in range: ClosedRange<Date>?) -> HistoryImportSelectionSummary {
        let selected = file.restricted(to: range)
        let pending = selected.workouts.filter {
            !alreadyImportedKeys.contains(HistoryImportMatching.dedupeKey(name: $0.name, startTime: $0.startTime))
        }
        let names = HistoryImportMatching.distinctExerciseNames(
            in: ParsedHistoryFile(workouts: pending, skippedCardioSetStartTimes: [], detectedWeightUnit: nil)
        )
        let newNames = names.filter { !libraryMatchedNames.contains(HistoryImportMatching.normalizedName($0)) }
        return HistoryImportSelectionSummary(
            workoutCount: selected.workouts.count,
            alreadyImportedCount: selected.workouts.count - pending.count,
            matchedExerciseCount: names.count - newNames.count,
            newExerciseNames: newNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            skippedCardioSetCount: selected.skippedCardioSetCount
        )
    }
}

/// The preview's numbers for one selected period.
struct HistoryImportSelectionSummary: Sendable, Equatable {
    let workoutCount: Int
    /// Already in history — skipped on import.
    let alreadyImportedCount: Int
    /// Distinct exercise names of the workouts to import that resolve to the library.
    let matchedExerciseCount: Int
    /// Distinct exercise names of the workouts to import that are not in the library, sorted.
    let newExerciseNames: [String]
    let skippedCardioSetCount: Int

    /// Workouts an import of this selection would actually write. Zero disables Import.
    var importableWorkoutCount: Int { workoutCount - alreadyImportedCount }
}

/// Quick period choices. They count back from the file's **newest workout**, not from
/// today: an export made months after leaving Strong would otherwise select nothing, and
/// for a user switching right now the two are the same.
enum HistoryImportPeriod: CaseIterable, Sendable {
    case everything, lastMonth, lastThreeMonths, lastYear

    /// The selected days, `earliest`'s day … `latest`'s day, both whole days inclusive.
    func dayRange(earliest: Date, latest: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let months: Int
        switch self {
        case .everything: return (earliest, latest)
        case .lastMonth: months = 1
        case .lastThreeMonths: months = 3
        case .lastYear: months = 12
        }
        let start = calendar.date(byAdding: .month, value: -months, to: latest) ?? earliest
        return (max(start, earliest), latest)
    }
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
