//
//  ChatFactProviding.swift
//  GymStreak
//
//  The data surface the chat tools call into. Each method resolves a question
//  entirely in Swift (querying SwiftData + delegating computation to the existing
//  domain services) and returns compact, pre-formatted fact lines. The on-device
//  model never sees raw sets and never performs arithmetic — it only verbalizes
//  what these methods return (fact-resolution doctrine, see docs/ai-coach.md).
//

import Foundation

/// Backing data layer for the chat tools.
///
/// `@MainActor` because every implementation touches SwiftData / the domain
/// services (which are all main-actor isolated). `Sendable` so a tool — whose
/// `call(arguments:)` runs off the main actor — can hold `any ChatFactProviding`
/// and `await` it to hop back to the main actor.
@MainActor
protocol ChatFactProviding: AnyObject, Sendable {

    /// Next-due date per scheduled routine, or a "nothing scheduled" line.
    func nextWorkoutFacts() -> String

    /// The all-time PR for a free-form exercise name: best set, estimated 1RM,
    /// and date — or disambiguation candidates / a not-found line with the
    /// closest known names. Name resolution happens here, not in the schema.
    func exercisePRFacts(exerciseName: String) -> String

    /// Workout count, volume, last workout, and current streak for a timeframe.
    func workoutHistoryFacts(timeframe: ChatHistoryTimeframe) -> String
}
