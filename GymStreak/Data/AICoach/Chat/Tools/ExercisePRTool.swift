//
//  ExercisePRTool.swift
//  GymStreak
//
//  Chat tool: "what is my bench press PR?" Wraps
//  `ChatFactProviding.exercisePRFacts`. The free-form exercise name is resolved
//  to the live library inside Swift (exact → contains → token overlap); a dynamic
//  `.anyOf` over all exercise names was rejected (token cost + fuzzy phrasing).
//

import FoundationModels
import os

struct ExercisePRTool: Tool {

    let name = "getExercisePR"
    let description = "Get the personal record (best set, estimated 1RM, date) for one named exercise. Use for questions about a specific exercise's PR, best, or max weight."

    @Generable
    struct Arguments {
        @Guide(description: "The exercise name copied verbatim from the user's message, in the same language. Do not translate it (e.g. keep 'Bankdrücken', do not change it to 'bench press').")
        let exerciseName: String
    }

    let facts: any ChatFactProviding

    func call(arguments: Arguments) async throws -> String {
        let result = await facts.exercisePRFacts(exerciseName: arguments.exerciseName)
        #if DEBUG
        // Fact log for the Phase 0 device drill: lets an on-screen answer be
        // checked against what the tool actually returned.
        Logger(subsystem: "app.gymstreak.aicoach", category: "ChatTool")
            .notice("getExercisePR(\(arguments.exerciseName, privacy: .public)) → \(result, privacy: .public)")
        #endif
        return result
    }
}
