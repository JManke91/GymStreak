//
//  NextWorkoutTool.swift
//  GymStreak
//
//  Chat tool: "when is my next workout?" Wraps `ChatFactProviding.nextWorkoutFacts`.
//  `Tool.call` runs off the main actor (`@concurrent`); the fact provider is
//  `@MainActor`, so `call` awaits it to hop back. Descriptions are kept terse —
//  every tool schema rides along on each request inside the ~4K-token budget.
//

import FoundationModels

struct NextWorkoutTool: Tool {

    let name = "getNextWorkout"
    let description = "Get when each scheduled routine is next due. Use for questions about the PLAN or SCHEDULE — what is next, upcoming, due, or planned for a day or week (e.g. 'what's on my plan this week'). Not for completed/past workouts."

    @Generable
    struct Arguments {}

    let facts: any ChatFactProviding

    func call(arguments: Arguments) async throws -> String {
        await facts.nextWorkoutFacts()
    }
}
