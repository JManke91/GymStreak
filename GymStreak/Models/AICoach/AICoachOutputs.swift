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
