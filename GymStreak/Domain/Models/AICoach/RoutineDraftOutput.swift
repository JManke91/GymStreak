//
//  RoutineDraftOutput.swift
//  GymStreak
//
//  The guided-generation schema for "describe a routine, get a draft".
//  See docs/ai-coach-routine-drafting.md.
//
//  **The model drafts; Swift decides and writes.** This is a `@Generable` output type
//  handed to `streamResponse(to:generating:)`, deliberately NOT a `Tool` that creates
//  the routine itself: `GenerationOptions.ToolCallingMode` does not exist on iOS 26.x,
//  so a tool call can be nudged by prompt but never forced, and this app has already
//  measured the model skipping a registered tool and mangling its arguments. A missed
//  read-tool call is a wrong sentence; a missed write-tool call would mean the person
//  believes a routine was created when it was not.
//
//  **No field here is Optional.** A `@Generable` optional has already produced the
//  literal string "nil" in rendered output in this app, so "the description did not say"
//  is carried by a sentinel number and decided in Swift by `RoutineDraftGrounder`.
//  Ticket 05 revisits this deliberately when rep goals and rest times arrive.
//
//  **No guide here names an exercise, a weight, a rep count or a unit word.** A
//  `@Guide(description:)` is placed verbatim into the prompt, so a literal in one is
//  indistinguishable from the reader's own input — the failure mode that once presented
//  an example `87.5 kg` to a reader as their training data. Pinned by
//  `CoachPromptGroundingTests`. See docs/ai-coach.md § "Prompt grounding rules".
//

import FoundationModels

@Generable
struct RoutineDraftOutput {

    @Guide(description: "A short name for this routine, written in the same language as the description. When the description names the workout, use that name; otherwise name it after what it trains. Never a sentence, never advice.")
    let routineName: String

    @Guide(
        description: "Every exercise the description names, in the order the description names them. Never add an exercise the description does not name, and never leave one out.",
        .minimumCount(1),
        .maximumCount(12)
    )
    let exercises: [RoutineDraftExercise]
}

@Generable
struct RoutineDraftExercise {

    /// The copy order is all-caps and the no-translation half is spelled out for the
    /// same measured reason it is on `WorkoutAnalysisHighlight.exerciseName`: a
    /// "translate everything" rule reads an English exercise name inside a German
    /// sentence as something to translate. Swift matches this string against the live
    /// library across languages — the model's job is only to hand it over unchanged.
    @Guide(description: "COPY THE EXERCISE NAME FROM THE DESCRIPTION EXACTLY, LETTER FOR LETTER, IN THE SAME LANGUAGE THE DESCRIPTION WRITES IT IN. Never translate it, never shorten or expand it, never replace it with a similar exercise, and never name an exercise the description does not name.")
    let name: String

    @Guide(description: "How many sets the description gives for this exercise, copied digit for digit. Write the number zero when the description gives no set count — zero means the description did not say, never a guess of your own.")
    let setCount: Int

    @Guide(description: "How many repetitions per set the description gives for this exercise, copied digit for digit. Write the number zero when the description gives no repetition count — zero means the description did not say, never a guess of your own.")
    let reps: Int

    @Guide(description: "The load for one set of this exercise, as a plain number in the unit your instructions name. Never write the unit word beside it and never write a range. Write the number zero when the description gives no load, or when the exercise is done with body weight alone.")
    let weight: Double
}
