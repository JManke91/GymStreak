//
//  NextWorkoutTool.swift
//  GymStreak
//
//  Chat tool: "when is my next workout?" Wraps `ChatFactProviding.nextWorkoutFacts`.
//  This tool's own isolation is deliberately irrelevant: since audit P1.3 the fact
//  provider guarantees off-main execution itself, via `@concurrent` on its concrete
//  methods. Apple declares the `Tool.call` requirement `@concurrent`, but nothing here
//  depends on that reaching an unannotated witness. Descriptions are kept terse —
//  every tool schema rides along on each request inside the ~4K-token budget.
//

import FoundationModels
import os

struct NextWorkoutTool: Tool {

    let name = "getNextWorkout"
    let description = "Get when each scheduled routine is next due. Use for questions about the PLAN or SCHEDULE — what is next, upcoming, due, or planned for a day or week (e.g. 'what's on my plan this week'). Not for completed/past workouts."

    @Generable
    struct Arguments {}

    let facts: any ChatFactProviding

    func call(arguments: Arguments) async throws -> String {
        let result = await facts.nextWorkoutFacts()
        #if DEBUG
        // Fact log for the Phase 0 device drill: lets an on-screen answer be
        // checked against what the tool actually returned.
        Logger(subsystem: "app.gymstreak.aicoach", category: "ChatTool")
            .notice("getNextWorkout → \(result, privacy: .public)")
        #endif
        return result
    }
}
