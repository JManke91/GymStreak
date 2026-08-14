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

    var isComplete: Bool { totalSets > 0 && completedSets == totalSets }

    var repRangeText: String? {
        guard let min = targetRepMin, let max = targetRepMax else { return nil }
        return min == max ? "\(min)" : "\(min)–\(max)"
    }
}

// MARK: - Progressive-overload prompt

/// One exercise that currently qualifies for a mid-workout weight increase.
struct OverloadPromptCandidate: Equatable {
    let exerciseId: UUID
    let exerciseName: String
    let targetRepMax: Int
    let isAssistance: Bool
}

/// What an applied increase moved the routine template to — the contents of the
/// confirmation that replaces the suggestion.
struct AppliedOverload: Equatable {
    let exerciseName: String
    /// Nil for a nonuniform (pyramid/drop) scheme — applied, but with no single
    /// weight that is true of every set.
    let weight: Double?
    let reps: Int
    let setCount: Int
}

/// The one progressive-overload prompt the active-workout screen shows.
enum OverloadPrompt: Equatable {
    case suggestion(OverloadPromptCandidate)
    case applied(exerciseId: UUID, AppliedOverload)

    var exerciseId: UUID {
        switch self {
        case .suggestion(let candidate): candidate.exerciseId
        case .applied(let id, _): id
        }
    }

    var exerciseName: String {
        switch self {
        case .suggestion(let candidate): candidate.exerciseName
        case .applied(_, let applied): applied.exerciseName
        }
    }
}

/// Which exercise, if any, owns the screen-level overload prompt.
///
/// Pure so the *reachability* of the prompt is testable: it used to be decided
/// inside the expanded exercise card's view tree, where the very event that
/// qualified an exercise (its last set completed) also collapsed the card that
/// carried the banner — the banner flashed for one animation and was gone. The
/// rule now lives here and the screen renders whatever it returns.
///
/// `WatchSummaryOverloadPolicy` is the same arrangement on the Watch.
enum OverloadPromptPolicy {

    /// - Parameters:
    ///   - orderedExerciseIds: this workout's exercises in workout order. Also
    ///     the invalidation list: a removed exercise takes its prompt with it.
    ///   - candidates: the exercises qualifying *right now*, keyed by id.
    ///     Derived fresh every pass, so un-completing a set or lowering reps
    ///     below the goal drops the prompt on its own.
    ///   - dismissed: one-way for the session — dismissing is a decision, not a
    ///     deferral.
    ///   - applied: confirmations still on screen, keyed by exercise id.
    /// - Returns: the earliest still-pending prompt in workout order, or nil.
    ///   Never more than one: banners must not stack over a running workout.
    static func prompt(
        orderedExerciseIds: [UUID],
        candidates: [UUID: OverloadPromptCandidate],
        dismissed: Set<UUID>,
        applied: [UUID: AppliedOverload]
    ) -> OverloadPrompt? {
        for id in orderedExerciseIds {
            // An applied exercise still qualifies — `overloadAlreadyApplied`
            // short-circuits `workoutQualifiesForIncrease` to `true` — so the
            // `applied` check must come first, or the suggestion would come
            // back alongside its own confirmation.
            if let confirmation = applied[id] {
                return .applied(exerciseId: id, confirmation)
            }
            if let candidate = candidates[id], !dismissed.contains(id) {
                return .suggestion(candidate)
            }
        }
        return nil
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
