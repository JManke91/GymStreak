//
//  RoutineDrafting.swift
//  GymStreak
//
//  The drafting boundary for "describe a routine, get a draft": one on-device
//  generation session, behind a protocol the Presentation layer can depend on.
//  See docs/ai-coach-routine-drafting.md.
//

import Foundation

/// Streams routine drafts from a free-text description.
///
/// **The element type is a plain value, not `LanguageModelSession.ResponseStream`.**
/// `AICoachServicing` hands its ViewModels the framework stream directly, which is why
/// the four surfaces built on it can only ever be tested through a double that returns
/// `nil` — a `ResponseStream` has no public initializer, so no test can produce one
/// carrying content. (`CoachChatServicing` sidesteps this differently, by exposing
/// finished `messages` rather than a stream at all.) This surface has acceptance criteria about what
/// happens *while* and *after* a draft streams (the allowance unit is consumed once,
/// refunded on failure, and never consumed twice in one session), so the boundary is
/// drawn one step further out: `Data/` owns the framework types and maps each snapshot
/// into `RoutineDraftSnapshot`, and a test drives the ViewModel with an ordinary
/// `AsyncThrowingStream`.
///
/// `@MainActor` like the rest of the AI-coach protocol surface: the only conformer holds
/// a `LanguageModelSession`, whose off-main-actor threading contract Apple does not
/// document (docs/swift6-concurrency.md §9).
@MainActor
protocol RoutineDrafting: AnyObject {

    /// Warms the on-device model so the first draft starts faster. Safe to call more
    /// than once.
    func prewarm()

    /// Streams a draft of the routine `description` asks for.
    ///
    /// Each element is a cumulative snapshot: the routine name so far plus every
    /// exercise that is fully generated. The stream finishes by throwing when
    /// generation fails, and cancelling the consuming task cancels the generation.
    ///
    /// - Parameter weightUnit: the unit the reader types and reads weights in. It
    ///   reaches the instructions *and* is the unit every `RoutineDraftEntry.weight`
    ///   comes back in — `weightUnit` travels beside the input rather than inside it for
    ///   the same reason it does on `AICoachServicing`.
    func draft(
        from description: String,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error>
}
