//
//  WatchMuscleGroupLocalization.swift
//  GymStreakWatch Watch App
//
//  Display-time localization for the muscle group and equipment keys that reach
//  the watch. iOS syncs both as raw English keys (`WatchModels.swift`) and
//  localizes only when rendering — `MuscleGroups.displayName(for:)` there, these
//  helpers here — so the wire payload stays language-agnostic and a cached
//  routine never carries stale translations. See docs/watch-localization.md.
//
//  Extracted from `WorkoutExerciseCatalogView.swift`, where they were file-scope
//  helpers that the routine-facing views could not discover and therefore never
//  called (muscle groups rendered in English on a German watch).
//

import Foundation

/// The muscle group keys, mirroring iOS `MuscleGroups.allKeys`. Enumerable so
/// the anti-drift test can assert that this table and the iOS one describe the
/// same set of muscles. `General` is deliberately absent — iOS does not count
/// it as a muscle either; it is the wire's fallback and is handled by
/// `localizedWatchMuscleGroup(_:)` as its own case.
let watchMuscleGroupKeys: [String] = [
    "Biceps",
    "Triceps",
    "Forearms",
    "Chest",
    "Upper Chest",
    "Upper Back",
    "Lats",
    "Lower Back",
    "Shoulders",
    "Front Delts",
    "Side Delts",
    "Rear Delts",
    "Abs",
    "Obliques",
    "Quadriceps",
    "Hamstrings",
    "Glutes",
    "Calves",
    "Hip Flexors"
]

/// Localized display name for an English muscle group key; unknown values pass
/// through unchanged, so a key added on iOS renders as its English name rather
/// than as an empty row.
func localizedWatchMuscleGroup(_ value: String) -> String {
    switch value {
    // Not a muscle: what iOS puts on the wire when an exercise has no primary
    // muscle group (`WatchModels.swift`, `WatchWorkoutStructuralReducer`).
    case "General": String(localized: "General")
    case "Biceps": String(localized: "Biceps")
    case "Triceps": String(localized: "Triceps")
    case "Forearms": String(localized: "Forearms")
    case "Chest": String(localized: "Chest")
    case "Upper Chest": String(localized: "Upper Chest")
    case "Upper Back": String(localized: "Upper Back")
    case "Lats": String(localized: "Lats")
    case "Lower Back": String(localized: "Lower Back")
    case "Shoulders": String(localized: "Shoulders")
    case "Front Delts": String(localized: "Front Delts")
    case "Side Delts": String(localized: "Side Delts")
    case "Rear Delts": String(localized: "Rear Delts")
    case "Abs": String(localized: "Abs")
    case "Obliques": String(localized: "Obliques")
    case "Quadriceps": String(localized: "Quadriceps")
    case "Hamstrings": String(localized: "Hamstrings")
    case "Glutes": String(localized: "Glutes")
    case "Calves": String(localized: "Calves")
    case "Hip Flexors": String(localized: "Hip Flexors")
    default: value
    }
}

/// Localized display name for an equipment type raw value.
func localizedWatchEquipment(_ value: String) -> String {
    switch value {
    case "dumbbell": String(localized: "Dumbbell")
    case "barbell": String(localized: "Barbell")
    case "machine": String(localized: "Machine")
    case "cable": String(localized: "Cable")
    case "bodyweight": String(localized: "Bodyweight")
    default: value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
