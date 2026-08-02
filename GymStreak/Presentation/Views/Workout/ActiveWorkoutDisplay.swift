//
//  ActiveWorkoutDisplay.swift
//  GymStreak
//
//  Value structs the active-workout rows render from. Everything a row shows is
//  resolved once, in the parent's ForEach body, so no row body walks a SwiftData
//  relationship (`setsList`, the routine slot behind a swap, the library
//  exercise behind an equipment icon) — see the main-thread rules in CLAUDE.md.
//

import Foundation

/// Which value of a set is being edited. Lives here rather than in the row view
/// because `WorkoutViewModel.updateSet(_:in:reps:weight:propagating:)` takes it.
enum WorkoutSetField {
    case reps
    case weight
}

/// Everything the collapsed row and the expanded card header of one exercise
/// need. Built by `ActiveWorkoutView` per visible exercise.
struct WorkoutExerciseDisplay: Identifiable, Equatable {
    let id: UUID
    let name: String
    let muscleGroups: [String]
    let equipmentType: EquipmentType
    let completedSets: Int
    let totalSets: Int
    /// Weight of the first set — the "what am I lifting here" hint on collapsed rows.
    let leadWeight: Double
    let isAssistance: Bool
    let restTime: TimeInterval
    let targetRepMin: Int?
    let targetRepMax: Int?
    /// Name of the originally planned exercise when this slot was swapped.
    let swappedFromName: String?
    /// A swap is still possible (no set logged yet and alternatives exist).
    let canSwap: Bool
    /// Alternatives exist but a logged set locked the swap — shows the lock affordance.
    let isSwapLocked: Bool
    let isInSuperset: Bool
    /// Every logged set hit the rep goal's upper limit — the progressive-overload
    /// nudge. Resolved here because the model's version walks `setsList`.
    let allCompletedSetsAtUpperLimit: Bool

    var isComplete: Bool { totalSets > 0 && completedSets == totalSets }

    var repRangeText: String? {
        guard let min = targetRepMin, let max = targetRepMax else { return nil }
        return min == max ? "\(min)" : "\(min)–\(max)"
    }
}

/// Everything one set row renders. `id` is the `WorkoutSet`'s id — the parent
/// resolves the model back from it when a callback fires.
struct WorkoutSetDisplay: Identifiable, Equatable {
    let id: UUID
    /// 1-based position shown as "01", "02", …
    let number: Int
    let reps: Int
    let weight: Double
    let plannedReps: Int
    let plannedWeight: Double
    let isCompleted: Bool
    let completedAt: Date?
    let isAssistance: Bool
    let targetRepMin: Int?
    let targetRepMax: Int?

    /// The logged reps miss the exercise's rep goal in either direction.
    var isOutsideRepRange: Bool {
        guard let min = targetRepMin, let max = targetRepMax else { return false }
        return reps < min || reps > max
    }

    /// The rep goal's upper limit is reached — the cue that precedes a weight increase.
    var isAtUpperRepLimit: Bool {
        guard let max = targetRepMax else { return false }
        return reps >= max
    }
}

/// One set row's model object paired with the values it renders, so the row list
/// is driven by a single source instead of two positionally-aligned arrays.
struct WorkoutSetRowItem: Identifiable {
    let set: WorkoutSet
    let display: WorkoutSetDisplay
    var id: UUID { display.id }
}

/// Formatting shared by the set rows, the value keypad and the exercise headers.
/// Kept as static members so no formatter is allocated inside a `body`.
enum WorkoutValueFormatting {
    /// Trims trailing zeros: 90 → "90", 37.5 → "37,5" (locale separator).
    static func weight(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%g", rounded)
            .replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    /// mm:ss for the rest countdown, h:mm:ss once a workout passes the hour —
    /// without the hour branch a 75-minute session would read "75:23".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
