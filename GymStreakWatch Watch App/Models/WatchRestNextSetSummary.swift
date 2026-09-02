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
    /// The exercise the target belongs to, but **only when it is not the one the
    /// user has just been doing** — `nil` in the common case of another set of
    /// the same exercise.
    ///
    /// A bare `80 kg × 8` is fine while the exercise continues and actively
    /// misleading when it does not: the user's next physical action is to load a
    /// bar, and they would load it for the wrong movement. Two paths reach that
    /// state — finishing an exercise's last set, and **every** superset round
    /// rollover, since a round's rest is followed by the next round's *first*
    /// exercise and therefore never by the one just performed.
    let exerciseName: String?

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
    /// `startedAfterExerciseID` is the *other* half of that: the exercise the
    /// rest was started for, which the cursor has already left behind. It is
    /// what makes "did the exercise change?" answerable at all, and it is
    /// **required rather than defaulted** — its absence silently disables the
    /// naming, which is the one failure this seam exists to prevent. Pass `nil`
    /// only where the origin is genuinely unknown (before the session's first
    /// rest, or after a mid-rest relaunch); the line then reads exactly as it
    /// does for a same-exercise rest.
    ///
    /// Compared by **id, not index**: `navigateToNextExercise` and the
    /// direct-jump path move the cursor during a rest, and an index would then
    /// name whatever now sits at the old position.
    ///
    /// `nil` for indices outside the workout. It is a defensive fallback, not a
    /// designed state: a rest never starts when no incomplete set remains
    /// (`applyToggleSetCompletion` takes the auto-finish path instead), so the
    /// full-screen timer cannot be up without a next set.
    static func target(
        in exercises: [ActiveWorkoutExercise],
        exerciseIndex: Int,
        setIndex: Int,
        startedAfterExerciseID: UUID?,
        unit: WeightUnit
    ) -> WatchRestNextSetSummary? {
        guard exercises.indices.contains(exerciseIndex) else { return nil }
        let exercise = exercises[exerciseIndex]
        guard exercise.sets.indices.contains(setIndex) else { return nil }
        let set = exercise.sets[setIndex]

        // An unknown origin is treated as "same exercise": naming one that the
        // user is already doing is noise, and this line has no width to spend on
        // a guess.
        let changedExerciseName: String? = {
            guard let startedAfterExerciseID,
                  startedAfterExerciseID != exercise.id else { return nil }
            return exercise.name
        }()

        return summary(
            reps: set.plannedReps,
            kilograms: set.plannedWeight,
            exerciseName: changedExerciseName,
            in: unit
        )
    }

    // MARK: - Formatting

    private static func summary(
        reps: Int,
        kilograms: Double,
        exerciseName: String?,
        in unit: WeightUnit
    ) -> WatchRestNextSetSummary {
        let repsText = repsPhrase(reps)

        // Bodyweight carries no weight to show — printing "0 kg" is what
        // `WatchExercise.setsSummary` already refuses to do, so the rep count
        // stands alone and keeps its word, which there is now room for.
        guard kilograms > 0 else {
            return WatchRestNextSetSummary(
                exerciseName: exerciseName,
                display: repsText,
                spoken: spokenPhrase(exerciseName: exerciseName, target: repsText)
            )
        }

        let written = WatchWeightFormatting.label(kilograms, in: unit)
        let spokenWeight = WatchWeightFormatting.labelled(
            WatchWeightFormatting.number(kilograms, in: unit),
            in: unit,
            unitWord: WatchWeightFormatting.spokenUnitWord(unit)
        )
        return WatchRestNextSetSummary(
            exerciseName: exerciseName,
            // "80 kg × 8", not "80 kg × 8 reps": this line shares a caption slot
            // with width-critical neighbours, and the multiplication sign needs
            // no translation. The spoken form spells the rep count out instead.
            display: "\(written) × \(reps)",
            spoken: spokenPhrase(
                exerciseName: exerciseName,
                target: "\(spokenWeight), \(repsText)"
            )
        )
    }

    private static func repsPhrase(_ reps: Int) -> String {
        String(
            localized: "\(reps) reps",
            comment: "Rep count of the next set on the rest timer, e.g. \"8 reps\""
        )
    }

    /// "Next set 80 kilograms, 8 reps" — with the exercise named first when it
    /// changed, since that is the part a listener cannot infer.
    ///
    /// No new String Catalog key: the name is folded into the existing
    /// announcement's argument, which keeps one phrase to translate instead of
    /// two that would have to stay in sync.
    private static func spokenPhrase(exerciseName: String?, target: String) -> String {
        guard let exerciseName else { return nextSetPhrase(target) }
        // No punctuation before the name. A comma there would read better in
        // isolation, but `"Next set %@"` substitutes after a space, so it comes
        // out as "Next set , Kniebeuge" — a stray space is worse than the
        // missing pause, and splitting the phrase into two keys to avoid it
        // trades one translated string for two that must agree.
        return nextSetPhrase("\(exerciseName), \(target)")
    }

    private static func nextSetPhrase(_ target: String) -> String {
        String(
            localized: "Next set \(target)",
            comment: "VoiceOver announcement of what the upcoming set asks for"
        )
    }
}
