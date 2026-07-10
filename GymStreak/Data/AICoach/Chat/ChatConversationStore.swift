//
//  ChatConversationStore.swift
//  GymStreak
//
//  Local-only JSON persistence for the chat conversation (Phase 1 of
//  docs/ai-coach-chat-plan.md). Stores the visible message list + per-turn
//  topics in Application Support, mirroring the `AICoachCache` pattern.
//  Deliberately NOT a SwiftData `@Model`: chat history must never enter the
//  CloudKit-synced container (on-device privacy guarantee, and no CloudKit
//  schema deploy). The FoundationModels `Transcript` is NOT persisted — on
//  restore the service rebuilds a fresh session from a
//  `ChatOverflowPolicy.digest` of these messages.
//

import Foundation
import os

@MainActor
final class ChatConversationStore {

    /// Everything needed to restore the conversation on a later launch.
    struct Snapshot: Codable {
        var messages: [CoachChatMessage]
        var turnTopics: [String]
    }

    private let fm = FileManager.default
    private let fileURL: URL
    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "ChatConversationStore")

    /// - Parameter directory: override for tests; defaults to
    ///   `Application Support/AICoachChat/`.
    init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let support = try! fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            dir = support.appending(path: "AICoachChat", directoryHint: .isDirectory)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appending(path: "conversation.json", directoryHint: .notDirectory)
    }

    /// The persisted conversation, or nil if none exists / it can't be decoded.
    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            logger.error("chat store decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Persists the conversation. In-flight (`.streaming`) messages are dropped —
    /// a turn is only durable once it finished or failed.
    func save(messages: [CoachChatMessage], turnTopics: [String]) {
        let snapshot = Snapshot(
            messages: messages.filter { $0.phase != .streaming },
            turnTopics: turnTopics
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("chat store write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the persisted conversation ("New chat").
    func clear() {
        try? fm.removeItem(at: fileURL)
    }
}
