//
//  ChatOverflowPolicyTests.swift
//  GymStreakTests
//
//  Validates the automatic context-overflow mechanism (the part that is our
//  code's responsibility): the proactive-condense threshold, the chars/3.5
//  fallback estimate, the deterministic digest, and markdown stripping. The
//  live-model behaviour after a real condense is a device-only checkpoint.
//

import Testing
@testable import GymStreak

@Suite
@MainActor
struct ChatOverflowPolicyTests {

    @Test func condensesOnlyAboveSeventyPercentOfUsableContext() {
        // contextSize 4096 − 800 reserve = 3296 usable → threshold Int(3296 × 0.7) = 2307.
        #expect(ChatOverflowPolicy.shouldCondense(usedTokens: 2308, contextSize: 4096))
        #expect(!ChatOverflowPolicy.shouldCondense(usedTokens: 2307, contextSize: 4096))
        #expect(!ChatOverflowPolicy.shouldCondense(usedTokens: 2000, contextSize: 4096))
    }

    @Test func estimatedTokensIsCharsOverThreePointFivePlusToolSchema() {
        let messages = [CoachChatMessage(role: .user, text: String(repeating: "x", count: 350), phase: .final)]
        // 350 / 3.5 = 100, + 220 tool-schema estimate = 320.
        #expect(ChatOverflowPolicy.estimatedTokens(messages: messages) == 320)
    }

    @Test func digestKeepsRecentExchangesVerbatimAndOlderTopics() {
        let messages = [
            CoachChatMessage(role: .user, text: "Q1", phase: .final),
            CoachChatMessage(role: .assistant, text: "A1", phase: .final),
            CoachChatMessage(role: .user, text: "Q2", phase: .final),
            CoachChatMessage(role: .assistant, text: "A2", phase: .final),
            CoachChatMessage(role: .user, text: "Q3", phase: .final),
            CoachChatMessage(role: .assistant, text: "A3", phase: .final),
        ]
        let digest = ChatOverflowPolicy.digest(
            messages: messages,
            turnTopics: ["asked one", "asked two", "asked three"]
        )
        // Last 4 finalized messages verbatim.
        #expect(digest.contains("User: Q3"))
        #expect(digest.contains("Coach: A3"))
        #expect(digest.contains("User: Q2"))
        // Older topics = all but the last two turns.
        #expect(digest.contains("asked one"))
        #expect(!digest.contains("asked three"))
    }

    @Test func digestSkipsStreamingAndEmptyMessages() {
        let messages = [
            CoachChatMessage(role: .user, text: "Q1", phase: .final),
            CoachChatMessage(role: .assistant, text: "", phase: .streaming), // in-flight, excluded
        ]
        let digest = ChatOverflowPolicy.digest(messages: messages, turnTopics: [])
        #expect(digest.contains("User: Q1"))
        #expect(!digest.contains("Coach:"))
    }

    @Test func stripMarkdownRemovesEmphasisMarkers() {
        #expect(CoachChatService.stripMarkdown("**Push:** and `code` and __x__") == "Push: and code and x")
    }
}
