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
//  That still holds for the rep-range goal and the rest time (ticket 05), which are
//  genuinely absent most of the time: an empty range span and an `unstated` rest unit
//  are their "did not say", and Swift maps them to `nil` / the 60 s default.
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

    @Guide(description: "A short name for this routine, in the same language as the description, taken from the description's own words for the workout. When the description gives the workout no name and does not say what kind of workout it is, write no name at all. Never make a name up, never a sentence, never advice.")
    let routineName: String

    /// No minimum count, deliberately. A `.minimumCount(1)` here forced the model to
    /// produce an exercise for "a push routine" — guided generation cannot emit fewer
    /// than the schema demands — which is exactly the invention this surface exists to
    /// prevent. An empty list is Swift's cue to ask (`GroundedRoutineDraft.gaps`).
    @Guide(
        description: "Every exercise the description names, in the order the description names them. Never add an exercise the description does not name, and never leave one out. Add an exercise to this list only when the description names it.",
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

    /// The rep-range goal is the **words** the person used for it, not two numbers the
    /// model derives. A `.pattern` guide constrains decoding to "number, separator,
    /// number" (or nothing), so the model points at text rather than composing figures.
    /// Measured (2026-09-27, macOS 27 on-device model): the former `repRangeLow`/`High`
    /// Int pair drafted the terse "3x8-12" as 6–12 on most runs; this span copies it as
    /// "8-12" on every run. When no range is stated the span is often junk ("8-8",
    /// "8-60") — which is why Swift keeps a span only when it parses as low < high *and*
    /// that exact pair was typed (`RoutineDraftGrounder.repRangeGoal(span:figures:)`).
    /// An empty String, never an optional, carries "no range".
    @Guide(
        description: "The repetition range the description gives as the goal for this exercise, copied exactly as written: both ends and the word or dash between them. Write nothing when the description gives no range for this exercise. A single repetition count is not a range.",
        .pattern(/(\d+ ?(-|–|bis|to) ?\d+)?/)
    )
    let repRange: String

    /// Rest is an amount plus the unit word beside it — never two numeric fields. Device
    /// round 8 (2026-09-27) measured the split `restMinutes`/`restSeconds` version: the
    /// model wrote "90 Sekunden" into the minutes field every time, the first rest-shaped
    /// slot it met. Naming the unit first and copying the number second keeps the model a
    /// copier, and Swift does the conversion.
    @Guide(description: "The unit word the description uses for the rest time between sets of this exercise. When the description gives one rest time for the whole workout, it applies to this exercise too. Choose unstated when the description gives no rest time.")
    let restUnit: RoutineDraftRestUnit

    @Guide(description: "The rest time between sets, copied digit for digit from the description, in the unit chosen above. Write the number zero when the description gives no rest time. Never a weight.")
    let restAmount: Double

}

/// The unit of a drafted rest time, as the description words it. `unstated` is a case,
/// not an optional, for the same reason nothing else in this schema is optional.
@Generable
enum RoutineDraftRestUnit {
    case unstated
    case seconds
    case minutes
}
