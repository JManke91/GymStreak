//
//  WorkoutHistoryTool.swift
//  GymStreak
//
//  Chat tool: "how many workouts this week?" Wraps
//  `ChatFactProviding.workoutHistoryFacts`. The timeframe is a `@Generable` enum
//  so guided generation constrains it to a known period at the decoding level.
//

import FoundationModels
import os

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
        let result = await facts.workoutHistoryFacts(timeframe: arguments.timeframe)
        #if DEBUG
        // Fact log for the Phase 0 device drill: lets an on-screen answer be
        // checked against what the tool actually returned.
        Logger(subsystem: "app.gymstreak.aicoach", category: "ChatTool")
            .notice("getWorkoutHistory(\(arguments.timeframe.rawValue, privacy: .public)) → \(result, privacy: .public)")
        #endif
        return result
    }
}
