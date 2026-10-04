//
//  HistoryImportMatching.swift
//  GymStreak
//
//  The import's matching, dedupe and conversion rules (docs/history-import.md §3).
//  Pure and isolation-agnostic: the import model actor calls it from its own executor.
//

import Foundation

/// A library exercise reduced to what the import needs to attach history to it.
struct HistoryImportLibraryEntry: Sendable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
}

enum HistoryImportMatching {

    /// Case- and whitespace-insensitive identity of an exercise or workout name:
    /// lowercased, trimmed, inner runs of whitespace collapsed to one space.
    static func normalizedName(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// A workout already in history has the same start second and the same name.
    /// Seconds are the file's precision, so sub-second residue must not split a match.
    static func dedupeKey(name: String, startTime: Date) -> String {
        "\(Int(startTime.timeIntervalSince1970.rounded()))|\(normalizedName(name))"
    }

    /// Normalized name → the library exercise imported history attaches to.
    ///
    /// CloudKit cannot enforce unique names, so two exercises may share one; the oldest
    /// (then smallest id) wins — the same deterministic pick `DefaultContentSeeder` makes.
    static func libraryIndex(_ entries: [HistoryImportLibraryEntry]) -> [String: HistoryImportLibraryEntry] {
        var index: [String: HistoryImportLibraryEntry] = [:]
        for entry in entries {
            let key = normalizedName(entry.name)
            guard !key.isEmpty else { continue }
            if let current = index[key],
               (current.createdAt, current.id.uuidString) <= (entry.createdAt, entry.id.uuidString) {
                continue
            }
            index[key] = entry
        }
        return index
    }

    /// Every distinct exercise name of the file (by normalized name), in its first spelling.
    static func distinctExerciseNames(in file: ParsedHistoryFile) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for workout in file.workouts {
            for exercise in workout.exercises where seen.insert(normalizedName(exercise.name)).inserted {
                names.append(exercise.name)
            }
        }
        return names
    }

    /// A file weight → the canonical kilograms to store (`docs/weight-unit-preference.md` §2).
    static func storedKilograms(_ fileWeight: Double, fileUnit: WeightUnit) -> Double {
        fileUnit.kilograms(fromDisplay: fileWeight)
    }

    /// Equipment and load behaviour for an exercise created from a Strong name, read from
    /// Strong's `(Barbell)`-style suffix. Anything unrecognised is a plain dumbbell-default
    /// resistance exercise, exactly like a user-created one.
    static func customExerciseTraits(for name: String) -> (EquipmentType, ExerciseLoadBehavior) {
        let lowered = name.lowercased()
        if lowered.contains("(assisted)") { return (.bodyweight, .counterweightAssistance) }
        if lowered.contains("(barbell)") { return (.barbell, .resistance) }
        if lowered.contains("(machine)") || lowered.contains("(smith machine)") { return (.machine, .resistance) }
        if lowered.contains("(cable)") { return (.cable, .resistance) }
        if lowered.contains("(bodyweight)") || lowered.contains("(weighted)") { return (.bodyweight, .resistance) }
        return (.dumbbell, .resistance)
    }
}
