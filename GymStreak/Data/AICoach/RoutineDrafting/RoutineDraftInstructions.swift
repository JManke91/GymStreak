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
        - Use ONLY what the person says. Never add an exercise they do not name, never leave out one they do name, and never replace an exercise with a similar one.
        - Add an exercise only when the person names it. When they name none, the list stays without entries: the app asks them which ones they want, and a guess of yours is never wanted.
        - Keep the exercises in the order the person lists them.
        - Copy each exercise name exactly as the person writes it, letter for letter, in the same language. Never translate it, never shorten or expand it, and never correct its spelling.
        - Copy every set count, repetition count and weight from the person's words digit for digit. Never do arithmetic, never round a figure, and never invent one.
        - When the person gives no set count, no repetition count, no weight or no rest time for an exercise, write the number zero for that value. Zero means they did not say. It is never a guess of your own, and a guess is never wanted.
        - Fill the repetition range only when the person states a range of repetitions for that exercise, copied exactly as they wrote it. A single repetition count is not a range, and most exercises have none.
        - Copy a rest time between sets as the person writes it, whole minutes and seconds apart. A rest time given once for the whole workout applies to every exercise.
        - Write each weight as a plain number in the unit named above, with no unit word beside it and never as a range.
        - Name the routine in the same language the person writes in, using their own words for the workout. When they give it no name and do not say what kind of workout it is, write no name. Never make a name up.
        - Write no advice, no encouragement and no commentary. Fill the fields and nothing else.

        When the message has several lines:
        - The first line is the person's description. Each later line is their answer to a question the app asked about something the description left out, and says which question it answers.
        - Draft from all lines together, as one description. An answer that covers every exercise at once applies to every exercise it covers.
        - Never fill anything that no line covers.
        """
    }

    /// The message for one turn: every line the person has said, oldest first — the
    /// description, then each framed answer. Each turn goes to a fresh session with this
    /// alone, so the model never reads anything it wrote earlier.
    ///
    /// Line breaks *inside* a line become spaces: the instructions say the first line is
    /// the description, so a description typed over several lines must stay one line.
    static func prompt(from lines: [String]) -> String {
        lines
            .map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// One answer, framed with the question it answers, in words the model reads; the
    /// answer itself verbatim. English like the instructions; the answer
    /// stays in whatever language the person wrote it in.
    static func answer(_ answer: String, to gap: RoutineDraftGap) -> String {
        "Answer about \(question(for: gap)) — \(answer)"
    }

    private static func question(for gap: RoutineDraftGap) -> String {
        switch gap {
        case .exercises:
            "which exercises the routine should include"
        case .setCounts(let names):
            "how many sets to do of \(names.joined(separator: ", "))"
        case .name:
            "what the routine should be called"
        }
    }
}
