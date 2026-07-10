//
//  ChatConversationStoreTests.swift
//  GymStreakTests
//
//  Validates the local-only JSON persistence for the chat conversation
//  (Phase 1 of docs/ai-coach-chat-plan.md): round-trip, streaming-message
//  filtering, failed-message survival, and clear. Uses a temp directory via
//  the store's test seam.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ChatConversationStoreTests {

    private func makeStore() -> ChatConversationStore {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "ChatConversationStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return ChatConversationStore(directory: dir)
    }

    @Test func loadReturnsNilWhenNothingSaved() {
        #expect(makeStore().load() == nil)
    }

    @Test func roundTripsMessagesAndTopics() {
        let store = makeStore()
        let messages = [
            CoachChatMessage(role: .user, text: "What's my bench PR?", phase: .final),
            CoachChatMessage(role: .assistant, text: "Your best set is 100 kg × 5.", phase: .final),
        ]
        store.save(messages: messages, turnTopics: ["What's my bench PR?"])

        let snapshot = store.load()
        #expect(snapshot?.messages == messages)
        #expect(snapshot?.turnTopics == ["What's my bench PR?"])
    }

    @Test func dropsInFlightStreamingMessagesOnSave() {
        let store = makeStore()
        store.save(
            messages: [
                CoachChatMessage(role: .user, text: "Q", phase: .final),
                CoachChatMessage(role: .assistant, text: "partial…", phase: .streaming),
            ],
            turnTopics: ["Q"]
        )
        #expect(store.load()?.messages.map(\.phase) == [.final])
    }

    @Test func keepsFailedMessages() {
        let store = makeStore()
        store.save(
            messages: [
                CoachChatMessage(role: .user, text: "Q", phase: .final),
                CoachChatMessage(role: .assistant, text: "Something went wrong.", phase: .failed),
            ],
            turnTopics: ["Q"]
        )
        #expect(store.load()?.messages.map(\.phase) == [.final, .failed])
    }

    @Test func clearRemovesPersistedConversation() {
        let store = makeStore()
        store.save(
            messages: [CoachChatMessage(role: .user, text: "Q", phase: .final)],
            turnTopics: ["Q"]
        )
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func overwritesPreviousSnapshot() {
        let store = makeStore()
        store.save(
            messages: [CoachChatMessage(role: .user, text: "old", phase: .final)],
            turnTopics: ["old"]
        )
        let newer = [
            CoachChatMessage(role: .user, text: "old", phase: .final),
            CoachChatMessage(role: .assistant, text: "answer", phase: .final),
        ]
        store.save(messages: newer, turnTopics: ["old"])
        #expect(store.load()?.messages == newer)
    }
}
