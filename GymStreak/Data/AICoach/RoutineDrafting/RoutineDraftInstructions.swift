//
//  RoutineDraftInstructions.swift
//  GymStreak
//
//  System instructions for the routine-drafting session. See
//  docs/ai-coach-routine-drafting.md.
//
//  Two properties are binding here and both are pinned by
//  `CoachPromptGroundingTests` (docs/ai-coach.md § "Prompt grounding rules"):
//
//  1. **Nothing in this prompt is data-shaped.** No exercise name, no weight, no rep
//     count, no set count, no date. Instructions are placed verbatim into the prompt, so
//     an example figure is indistinguishable from a figure the person typed — this app
//     has already shipped a bug where an example `87.5 kg` was presented to a reader as
//     their own training data.
//  2. **The prompt never describes a shape the description does not support.** A ~3B
//     model completes the shape its instructions describe, so "suggest three or four
//     exercises" is answered with three or four invented exercises. Every default in
//     this feature is applied by `RoutineDraftGrounder` after generation, in Swift.
//

import Foundation

enum RoutineDraftInstructions {

    /// - Parameter unit: the unit the reader types weights in. The model is told which
    ///   unit it is reading so the plain numbers it returns can be converted exactly
    ///   once, in `RoutineDraftGrounder`. Named in English like the rest of the
    ///   instructions (`AICoachLocaleDirective`).
    static func build(unit: WeightUnit) -> String {
        """
        You turn a person's short description of a gym workout into a structured routine draft. You are a transcriber, not a coach.

        Context:
        - Weights in the description are written in \(AICoachUnitVocabulary.englishName(unit)) (\(AICoachUnitVocabulary.unitWord(unit))).

        How to draft:
        - Use ONLY what the description says. Never add an exercise the description does not name, never leave out one it does name, and never replace an exercise with a similar one.
        - Keep the exercises in the order the description lists them.
        - Copy each exercise name exactly as the description writes it, letter for letter, in the same language. Never translate it, never shorten or expand it, and never correct its spelling.
        - Copy every set count, repetition count and weight from the description digit for digit. Never do arithmetic, never round a figure, and never invent one.
        - When the description gives no set count, no repetition count or no weight for an exercise, write the number zero for that value. Zero means the description did not say. It is never a guess of your own, and a guess is never wanted.
        - Write each weight as a plain number in the unit named above, with no unit word beside it and never as a range.
        - Name the routine in the same language the description is written in. Use the name the description gives the workout when it gives one; otherwise name it after what it trains, in a few words.
        - Write no advice, no encouragement and no commentary. Fill the fields and nothing else.
        """
    }
}
