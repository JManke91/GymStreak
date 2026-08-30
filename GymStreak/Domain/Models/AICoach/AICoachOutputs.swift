//
//  AICoachOutputs.swift
//  GymStreak
//
//  @Generable output structs consumed by AICoachService. Most are also Codable so
//  AICoachCache can persist them as JSON directly; `ExerciseDeepDiveOutput` deliberately
//  is not — what that surface caches is `ExerciseDeepDiveNarrative`, which adds a field
//  the model never produces.
//

import FoundationModels

// MARK: - Post-Workout Recap

@Generable
struct PostWorkoutRecapOutput: Codable {
    @Guide(description: "Two to three sentence narrative in the user's locale. No emoji, no exclamation marks, no medical or prescriptive advice. Must mention overall session quality, any PR if present, and one observation about muscle group balance. Use only the values provided in the input.")
    let narrative: String
}

// MARK: - Period Recap

/// **No guide here names a unit.** `@Guide(description:)` is a macro-expanded literal
/// in a *static* generation schema, so it cannot carry a per-reader value the way the
/// system prompts can — and a guide hardcoding "kg" is exactly what taught the model to
/// write kilograms at a reader being handed pounds. The unit is named by the prompt and
/// carried by the figures; the guides say "copy it". See docs/weight-unit-preference.md §13.
@Generable
struct PeriodRecapOutput: Codable {
    @Guide(description: "One sentence in the user's locale rephrasing the input's 'Headline fact'. Never about total volume or session counts.")
    let headline: String

    @Guide(description: "Two to three short sentences in the user's locale: improved exercises with their exact gains copied from the input — figure and unit word together, exactly as written there — then declined ones, then unchanged ones by name. Mention the consistency fact when marked irregular.")
    let trendsNarrative: String

    /// **This guide names no programming construct**, and none may be added. It used to
    /// say *"Return nil when the input has no detected patterns"* — and on a device check
    /// the model answered that literally, writing the four-character string `nil` into the
    /// field, which the Auffälligkeiten card rendered verbatim (German, 2026-08-30). A
    /// `@Guide(description:)` is prompt text, so `nil` in it is a word to write, not an
    /// absence to produce. Ask for the absence in plain language instead.
    ///
    /// A Swift-side guard rejects a placeholder answer whatever arrives — the half of the
    /// guarantee that does not depend on the model obeying anything. See
    /// docs/ai-coach.md § "Prompt grounding rules", rule 4.
    @Guide(description: "The 'Detected patterns' statement reproduced as one sentence in the user's locale. OMIT THIS FIELD ENTIRELY when the input has no 'Detected patterns' section — do not return it empty, return nothing for it. Never fill it with a placeholder word, a dash, or a sentence explaining or apologising for the absence; whatever is written here is shown to the reader exactly as written.")
    let correlationHighlight: String?

    @Guide(description: "One sentence in the user's locale rephrasing the 'Closing fact'. When marked as a recommendation, one concrete suggestion; otherwise purely observational.")
    let closingSentence: String
}

// MARK: - Exercise Deep-Dive

/// The paragraphs the model writes for one exercise deep-dive — **one field per
/// paragraph**, not one `String` holding all of them.
///
/// Three rounds of prose rules ("output exactly 3 to 4 short paragraphs, 2-3 sentences
/// each") were ignored on every device check, in both prompts. Guided generation is
/// Apple's documented mechanism for controlling output *shape*, and no `@Guide` constraint
/// enforces a paragraph count inside a single `String` — so the shape moves into the type,
/// where each field is a paragraph by construction and carries its own all-caps grounding
/// constraint. `@Guide(description:)` is "effectively another way of prompting", and a
/// constraint attached to the one field it governs is a stronger lever than the same
/// sentence buried in a twelve-bullet instruction list.
///
/// Deliberately **not** `Codable`: what the cache and the screen hold is
/// `ExerciseDeepDiveNarrative`, which adds the peak sentence Swift composes and the model
/// never sees. See that type.
@Generable
struct ExerciseDeepDiveOutput {
    /// The content requirement leads and the constraint follows, deliberately. This guide
    /// used to open with `COPY THE INPUT'S 'History range' VALUE EXACTLY AS WRITTEN` — and
    /// on a device check the model did exactly that and nothing else, returning the bare
    /// string `Juli 2026 – August 2026` as the whole paragraph. An all-caps copy order at
    /// the head of a field is answered by copying; what the paragraph must *say* has to
    /// come first.
    @Guide(description: "Paragraph 1: two to three complete sentences in the reader's language saying how many sessions were analysed and over what period. Always write full sentences — a bare date range or a fragment is not an answer. Name the period with the input's 'History range' value exactly as written, and NAME NO OTHER PERIOD. NEVER WRITE A NUMBER THAT IS NOT IN THE INPUT.")
    let workload: String

    /// Optional because a blended view has no progression to state — and on a device check
    /// the model took that as permission to skip it on a *single-variant* view too, where
    /// it is the whole point of the surface. Hence the explicit "required whenever" half:
    /// optional is not the same as discretionary.
    ///
    /// `ExerciseDeepDiveViewModel` drops the field for a blended input whatever arrives —
    /// the only guarantee here that does not depend on the model obeying anything.
    @Guide(description: "Paragraph 2: two to three complete sentences in the reader's language about the overall change in estimated 1RM, and about the strongest improvement segment. THE INPUT GIVES YOU A CHANGE AND A PERCENTAGE, NEVER A STARTING OR ENDING 1RM VALUE — state the change itself, and NEVER NAME A FIRST OR MOST-RECENT 1RM FIGURE. Required whenever the input contains an 'Overall progression' block. OMIT THIS FIELD ONLY WHEN THE INPUT SAYS NO PROGRESSION FIGURE IS AVAILABLE. NEVER WRITE A FIGURE, A PERCENTAGE OR A PERIOD THAT IS NOT IN THE INPUT.")
    let progression: String?

    /// The no-advice rule lives here as well as in both prompts because the prompt copy of
    /// it was ignored: a device check produced "ein guter Indikator dafür, dass du deine
    /// Intensität etwas reduzieren solltest" — prescriptive training advice, from the
    /// field this guide governs.
    @Guide(description: "Paragraph 3: two to three complete sentences in the reader's language on the subject your instructions assign to it. State what the figures ARE, never what they MEAN for future training: NEVER TELL THE READER WHAT TO DO, never suggest changing weights, reps, intensity, volume or training frequency, never suggest resting or taking a break, and never mention injury or risk. NEVER WRITE A FIGURE, A DATE OR A TIMEFRAME THAT IS NOT IN THE INPUT.")
    let closing: String
}

// MARK: - Workout Analysis

/// What the model writes for a workout analysis — highlights and a closing sentence.
///
/// **There is no `headline` field**, and there deliberately is not one. It used to be
/// generated, and a device check returned *"Neuer Bestwert bei Bankdrücken"* for a session
/// without Bankdrücken in it: an exercise name lifted from a worked example in the
/// instructions. `WorkoutAnalysisInput.headlineSentence` composes that sentence in Swift
/// now and `WorkoutAnalysisNarrative` carries it, which is why this type is deliberately
/// **not** `Codable` — what the cache and the screen hold is the narrative.
@Generable
struct WorkoutAnalysisOutput {
    @Guide(description: "The 1 to 4 most notable exercises from the input, ordered: PRs first, then biggest improvements, then declines. Never include exercises done for the first time.", .minimumCount(1), .maximumCount(4))
    let exerciseHighlights: [WorkoutAnalysisHighlight]

    @Guide(description: "One short closing sentence in the user's locale with an observation about the session as a whole. Observational, not prescriptive. No dates. NAME ONLY EXERCISES THAT APPEAR IN THE INPUT, SPELLED EXACTLY AS THE INPUT SPELLS THEM — never translate an exercise name and never invent one.")
    let closingObservation: String
}

@Generable
struct WorkoutAnalysisHighlight: Codable, Equatable, Sendable {
    /// The copy order is all-caps and the no-translation half is spelled out because the
    /// prompt's "translate every word into the target language" rule reads an English
    /// exercise name in a German sentence as something to translate — which is how "Dip"
    /// once became "Bankdrücken" in the generated headline.
    @Guide(description: "COPY THE EXERCISE NAME FROM THE INPUT EXACTLY, LETTER FOR LETTER. Never translate, shorten or expand it, and never name an exercise the input does not list — an English name stays English in a German sentence.")
    let exerciseName: String

    @Guide(description: "Direction of change, derived from the verdict tag in the input: IMPROVED to improved, DECREASED to declined, UNCHANGED to unchanged, MIXED to mixed, NEW SETS to new.")
    let trend: WorkoutAnalysisTrend

    @Guide(description: "One short sentence (max 12 words) in the user's locale rephrasing this exercise's 'Fact' line with its exact numbers. Copy each weight with the unit word the input writes it with; rep changes always as reps — never mix the two units in one figure.")
    let detail: String
}

/// Direction of an exercise's change vs. the previous session.
///
/// Modeled as a `@Generable` enum so the on-device model is constrained at the
/// decoding level to exactly one of these cases — the same guarantee as a
/// `.anyOf` string guide, but type-safe with no string-to-enum mapping or
/// invalid-value fallback. `String`-backed for clean JSON in the disk cache.
@Generable
enum WorkoutAnalysisTrend: String, Codable, Equatable, Sendable {
    case improved
    case declined
    case unchanged
    case mixed
    case new
}
