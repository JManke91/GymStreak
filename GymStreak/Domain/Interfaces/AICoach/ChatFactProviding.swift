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
/// `Sendable` because a tool holds `any ChatFactProviding` and `FoundationModels`
/// requires tools to be `Sendable`. No `PersistentModel` crosses this boundary —
/// implementations own their persistence context and return only fact strings.
///
/// ⚠️ **The off-main guarantee is NOT provided by this protocol.** Every method here
/// reads the user's whole completed-workout history; on the main actor that is the
/// hang documented in `docs/history-performance.md`. Under
/// `SWIFT_APPROACHABLE_CONCURRENCY` (SE-0461, `nonisolated(nonsending)` by default) a
/// plain `nonisolated async` requirement runs on the **caller's** actor, and the caller
/// is a `FoundationModels.Tool` whose own isolation Apple does not document.
///
/// The guarantee lives on the conforming type instead: `ChatFactProvider`'s methods are
/// `@concurrent`. Whether annotating these *requirements* would also work is NOT
/// DOCUMENTED — SE-0461 never discusses protocol witnesses — so do not rely on it.
/// **Any new conformer that does real work must carry `@concurrent` on its own
/// methods.** See `docs/swift6-concurrency.md` §1.
///
/// Nothing here throws: a tool must always hand the model a fact line, so a failed
/// fetch degrades to the empty-database line rather than surfacing as a failed answer.
protocol ChatFactProviding: Sendable {

    /// Next-due date per scheduled routine, or a "nothing scheduled" line.
    func nextWorkoutFacts() async -> String

    /// The all-time PR for a free-form exercise name: best set, estimated 1RM,
    /// and date — or disambiguation candidates / a not-found line with the
    /// closest known names. Name resolution happens here, not in the schema.
    func exercisePRFacts(exerciseName: String) async -> String

    /// Workout count, volume, last workout, and current streak for a timeframe.
    func workoutHistoryFacts(timeframe: ChatHistoryTimeframe) async -> String
}
