//
//  AICoachOutputs.swift
//  GymStreak
//
//  @Generable output structs consumed by AICoachService.
//  Also Codable so AICoachCache can persist them as JSON.
//

import FoundationModels

// MARK: - Post-Workout Recap

@Generable
struct PostWorkoutRecapOutput: Codable {
    @Guide(description: "Two to three sentence narrative in the user's locale. No emoji, no exclamation marks, no medical or prescriptive advice. Must mention overall session quality, any PR if present, and one observation about muscle group balance. Use only the values provided in the input.")
    let narrative: String
}

// MARK: - Period Recap

@Generable
struct PeriodRecapOutput: Codable {
    @Guide(description: "One-line headline opening, in the user's locale, stating the most important metric.")
    let headline: String

    @Guide(description: "One to two paragraphs (3-6 sentences total) narrating the trends in the user's locale.")
    let trendsNarrative: String

    @Guide(description: "Short paragraph (2-3 sentences) on the most interesting correlation, in the user's locale. Return nil when no correlations were provided in the input. Do NOT write explanatory or apologetic text. nil means the UI hides this section.")
    let correlationHighlight: String?

    @Guide(description: "One forward-looking sentence in the user's locale. Observational, not prescriptive.")
    let closingSentence: String
}

// MARK: - Exercise Deep-Dive

@Generable
struct ExerciseDeepDiveOutput: Codable {
    @Guide(description: "Three to four short paragraphs in the user's locale, covering: (1) overall progression, (2) strongest period, (3) current state, (4) one observation correlating frequency with progression. Each paragraph 2-3 sentences. Use only data from the input.")
    let narrative: String
}

// MARK: - Workout Analysis

@Generable
struct WorkoutAnalysisOutput: Codable {
    @Guide(description: "One short sentence (max 14 words) in the user's locale summarizing the session vs. the previous one, based on total volume and set count. No dates.")
    let headline: String

    @Guide(description: "The 2 to 4 most notable exercises from the input, ordered: PRs first, then biggest improvements, then declines.", .minimumCount(2), .maximumCount(4))
    let exerciseHighlights: [WorkoutAnalysisHighlight]

    @Guide(description: "One short closing sentence in the user's locale with an observation about the session as a whole. Observational, not prescriptive. No dates.")
    let closingObservation: String
}

@Generable
struct WorkoutAnalysisHighlight: Codable {
    @Guide(description: "Exercise name copied exactly as written in the input.")
    let exerciseName: String

    @Guide(description: "Direction of change, derived from the verdict tag in the input: IMPROVED to improved, DECREASED to declined, UNCHANGED to unchanged, MIXED to mixed, NEW EXERCISE or NEW SETS to new.")
    let trend: WorkoutAnalysisTrend

    @Guide(description: "One short sentence (max 12 words) in the user's locale stating the concrete change with exact values from the input. Weight changes always in kg, rep changes always as reps — never mix the two units in one figure.")
    let detail: String
}

/// Direction of an exercise's change vs. the previous session.
///
/// Modeled as a `@Generable` enum so the on-device model is constrained at the
/// decoding level to exactly one of these cases — the same guarantee as a
/// `.anyOf` string guide, but type-safe with no string-to-enum mapping or
/// invalid-value fallback. `String`-backed for clean JSON in the disk cache.
@Generable
enum WorkoutAnalysisTrend: String, Codable {
    case improved
    case declined
    case unchanged
    case mixed
    case new
}
