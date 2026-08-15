//
//  CoachChatModels.swift
//  GymStreak
//
//  Domain models for the AI Coach chat assistant spike (see
//  docs/ai-coach-chat-feasibility.md). The visible message list is our own type,
//  deliberately decoupled from the FoundationModels `Transcript` — the transcript
//  is a token-budget-constrained working set the service condenses freely, while
//  the message list never shrinks.
//

import Foundation
import FoundationModels

/// A single visible chat message. The UI renders this array directly; it is not
/// the model's transcript (which the service may condense on overflow).
/// `Codable` so the finalized conversation persists across launches via
/// `ChatConversationStore` (local-only JSON, never the CloudKit container).
struct CoachChatMessage: Identifiable, Equatable, Codable {

    /// Who authored the message.
    enum Role: String, Codable {
        case user
        case assistant
    }

    /// Lifecycle of an assistant message (user messages are always `.final`).
    enum Phase: String, Codable, Equatable {
        /// Streaming tokens in — render with the live cursor.
        case streaming
        /// Generation finished successfully.
        case final
        /// Generation failed (error/guardrail) — render an inline error affordance.
        case failed
    }

    let id: UUID
    let role: Role
    /// Cumulative text. For a streaming assistant message this grows per snapshot.
    var text: String
    var phase: Phase

    init(id: UUID = UUID(), role: Role, text: String, phase: Phase) {
        self.id = id
        self.role = role
        self.text = text
        self.phase = phase
    }
}

/// How an assistant turn ended, reported to whoever started it.
///
/// It exists for the free-tier taster (docs/pro-subscription.md §5e): a message
/// costs the user one of their five monthly units, and charging for a generation
/// that errored is indefensible — so the caller has to learn the difference
/// without inspecting the message list. A cancelled turn that produced no text
/// counts as `.failed` for the same reason: the user got no answer.
enum CoachChatTurnOutcome: Sendable, Equatable {
    case completed
    case failed
}

/// Timeframe argument for the workout-history tool. A `@Generable` enum so guided
/// generation constrains the model at the decoding level to exactly one case —
/// the same guarantee the `WorkoutAnalysisTrend` output enum relies on. Lives in
/// `Domain/Models/AICoach` alongside `AICoachOutputs`, which likewise declares
/// `@Generable` types in the Domain layer for the AI Coach subsystem.
@Generable
enum ChatHistoryTimeframe: String, Codable, CaseIterable {
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    /// All history — use for "my last workout" / "most recent training" and
    /// all-time totals, where no bounded week/month window applies.
    case allTime
}
