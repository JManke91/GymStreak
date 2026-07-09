//
//  ChatOverflowPolicy.swift
//  GymStreak
//
//  Pure, testable context-overflow policy for the chat session: the
//  proactive-condense budget decision, the chars/3.5 fallback estimate, and the
//  deterministic Swift-side digest. Extracted from CoachChatService so the
//  overflow mechanism can be unit-tested without a live model.
//  See docs/ai-coach-chat-feasibility.md.
//

import Foundation

enum ChatOverflowPolicy {

    /// Context reserved for the answer + tool round-trip before condensing.
    static let reservedOutputTokens = 800
    /// Fraction of usable context that triggers a proactive condense.
    static let condenseThresholdFraction = 0.7
    /// Pre-26.4 estimate of the tool schemas (no `tokenCount` available then).
    static let estimatedToolSchemaTokens = 220

    /// Whether `usedTokens` crosses the proactive-condense threshold for a model
    /// whose full window is `contextSize`.
    static func shouldCondense(usedTokens: Int, contextSize: Int) -> Bool {
        let usable = max(1, contextSize - reservedOutputTokens)
        let threshold = Int(Double(usable) * condenseThresholdFraction)
        return usedTokens > threshold
    }

    /// chars/3.5 fallback estimate (pre-26.4, or when `tokenCount` fails).
    static func estimatedTokens(messages: [CoachChatMessage]) -> Int {
        let chars = messages.reduce(0) { $0 + $1.text.count }
        return Int(Double(chars) / 3.5) + estimatedToolSchemaTokens
    }

    /// Deterministic digest: last 2 exchanges (≤4 finalized messages) verbatim +
    /// a one-line topic list of older turns. No extra inference.
    static func digest(messages: [CoachChatMessage], turnTopics: [String]) -> String {
        let finalized = messages.filter { $0.phase == .final && !$0.text.isEmpty }
        let recentLines = finalized.suffix(4).map { message in
            (message.role == .user ? "User: " : "Coach: ") + message.text
        }.joined(separator: "\n")

        var parts: [String] = []
        let olderTopics = turnTopics.dropLast(2)
        if !olderTopics.isEmpty {
            parts.append("The user earlier asked about: \(olderTopics.joined(separator: "; ")).")
        }
        if !recentLines.isEmpty {
            parts.append("Most recent exchanges:\n\(recentLines)")
        }
        return parts.joined(separator: "\n")
    }
}
