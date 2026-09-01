//
//  WatchRestNextSetSummary.swift
//  GymStreakWatch Watch App
//
//  What the rest timer's caption slot says while a rest runs: the target of the
//  set the user is resting *for*. Turns the workout's plain values into the one
//  line the caption draws, and the phrase VoiceOver speaks for it.
//
//  Pure by construction — no view model, no SwiftUI — following the seam pattern
//  of `WatchWorkoutInteractionPolicy` and `WatchSummaryOverloadPolicy` in this
//  folder. That is what makes it testable: `WatchWorkoutViewModel` itself has no
//  coverage, so anything worth asserting on has to live outside it.
//

import Foundation

/// The next set's planned target, formatted for the rest timer.
///
/// Weight is stored in canonical kilograms everywhere and converted only here,
/// at the display seam, through `WatchWeightFormatting` — never
/// `.formatted(.measurement(...))`, which re-derives the unit from `Locale`
/// (see `docs/weight-unit-preference.md`).
struct WatchRestNextSetSummary: Equatable {
    /// The caption's line, without the dumbbell glyph the view prefixes:
    /// `"80 kg × 8"`, or `"8 reps"` for a bodyweight set.
    let display: String

    /// The same target spoken in full — "Next set 80 kilograms, 8 reps". The
    /// written unit word ("kg") is replaced by the spoken one so a screen reader
    /// does not say "kay gee".
    let spoken: String

    /// The target of the set at `(exerciseIndex, setIndex)`.
    ///
    /// While a rest is running those coordinates already point at the **next**
    /// set: `WatchWorkoutViewModel.advanceToNextSetAfterCompletion` moves them
    /// before the rest overlay mounts. There is deliberately no peek/lookahead
    /// concept here — this reads what the view model already says is current.
    ///
    /// `nil` for indices outside the workout. It is a defensive fallback, not a
    /// designed state: a rest never starts when no incomplete set remains
    /// (`applyToggleSetCompletion` takes the auto-finish path instead), so the
    /// full-screen timer cannot be up without a next set.
    static func target(
        in exercises: [ActiveWorkoutExercise],
        exerciseIndex: Int,
        setIndex: Int,
        unit: WeightUnit
    ) -> WatchRestNextSetSummary? {
        guard exercises.indices.contains(exerciseIndex) else { return nil }
        let sets = exercises[exerciseIndex].sets
        guard sets.indices.contains(setIndex) else { return nil }
        let set = sets[setIndex]
        return summary(reps: set.plannedReps, kilograms: set.plannedWeight, in: unit)
    }

    // MARK: - Formatting

    private static func summary(
        reps: Int,
        kilograms: Double,
        in unit: WeightUnit
    ) -> WatchRestNextSetSummary {
        let repsText = repsPhrase(reps)

        // Bodyweight carries no weight to show — printing "0 kg" is what
        // `WatchExercise.setsSummary` already refuses to do, so the rep count
        // stands alone and keeps its word, which there is now room for.
        guard kilograms > 0 else {
            return WatchRestNextSetSummary(display: repsText, spoken: nextSetPhrase(repsText))
        }

        let written = WatchWeightFormatting.label(kilograms, in: unit)
        let spokenWeight = WatchWeightFormatting.labelled(
            WatchWeightFormatting.number(kilograms, in: unit),
            in: unit,
            unitWord: WatchWeightFormatting.spokenUnitWord(unit)
        )
        return WatchRestNextSetSummary(
            // "80 kg × 8", not "80 kg × 8 reps": this line shares a caption slot
            // with width-critical neighbours, and the multiplication sign needs
            // no translation. The spoken form spells the rep count out instead.
            display: "\(written) × \(reps)",
            spoken: nextSetPhrase("\(spokenWeight), \(repsText)")
        )
    }

    private static func repsPhrase(_ reps: Int) -> String {
        String(
            localized: "\(reps) reps",
            comment: "Rep count of the next set on the rest timer, e.g. \"8 reps\""
        )
    }

    private static func nextSetPhrase(_ target: String) -> String {
        String(
            localized: "Next set \(target)",
            comment: "VoiceOver announcement of what the upcoming set asks for"
        )
    }
}
