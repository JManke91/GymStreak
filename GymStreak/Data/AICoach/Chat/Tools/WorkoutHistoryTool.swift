//
//  WorkoutHistoryTool.swift
//  GymStreak
//
//  Chat tool: "how many workouts this week?" Wraps
//  `ChatFactProviding.workoutHistoryFacts`. The timeframe is a `@Generable` enum
//  so guided generation constrains it to a known period at the decoding level.
//

import FoundationModels

struct WorkoutHistoryTool: Tool {

    let name = "getWorkoutHistory"
    let description = "Get COMPLETED/past workout stats for a timeframe: count, total volume, most recent workout, current streak. Use for how many workouts were done, past activity, streaks, or the last/most-recent workout. Not for the upcoming plan or schedule."

    @Generable
    struct Arguments {
        @Guide(description: "Which period to summarize. Use allTime for the last/most-recent workout or all-time totals.")
        let timeframe: ChatHistoryTimeframe
    }

    let facts: any ChatFactProviding

    func call(arguments: Arguments) async throws -> String {
        await facts.workoutHistoryFacts(timeframe: arguments.timeframe)
    }
}
