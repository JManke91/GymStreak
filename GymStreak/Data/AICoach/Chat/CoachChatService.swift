//
//  CoachChatService.swift
//  GymStreak
//
//  Session-holding singleton for the chat assistant spike. Owns one retained
//  `LanguageModelSession` (multi-turn), the 3 tools, the visible message list,
//  and the automatic context-overflow handling (proactive digest condensation +
//  reactive retry). Survives navigation; resets on app termination or an explicit
//  "New chat". See docs/ai-coach-chat-feasibility.md.
//
//  Verified against iPhoneOS26.5.sdk (Step 0): plain-text streaming via
//  `streamResponse(to:options:) -> ResponseStream<String>` (cumulative
//  `snapshot.content`), tool calls resolved transparently inside the stream, no
//  `ToolCallingMode` (invocation is instructions-driven).
//

import Foundation
import FoundationModels
import os

@Observable
@MainActor
final class CoachChatService: CoachChatServicing {

    // MARK: - Singleton

    static let shared = CoachChatService()
    private init() {}

    // MARK: - Tuning

    /// Output-token cap per turn (answer + tool round-trip).
    private static let maxResponseTokens = 500
    // Overflow budgeting + digest live in `ChatOverflowPolicy` (pure + unit-tested).

    // MARK: - Observable state

    private(set) var messages: [CoachChatMessage] = []
    private(set) var isResponding = false

    // MARK: - Private

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "CoachChatService")
    private let availability = AICoachAvailability.shared

    private var factProvider: ChatFactProviding?
    private var tools: [any Tool] = []
    private var session: LanguageModelSession?
    private var streamTask: Task<Void, Never>?

    /// One short topic per user turn (captured at send time), used to build the
    /// digest cheaply when the transcript is condensed. Deterministic — no extra
    /// inference. Indexed by turn, parallel to the user messages.
    private var turnTopics: [String] = []

    // MARK: - Configuration

    func configure(factProvider: ChatFactProviding) {
        guard self.factProvider == nil else { return }
        self.factProvider = factProvider
        self.tools = [
            NextWorkoutTool(facts: factProvider),
            ExercisePRTool(facts: factProvider),
            WorkoutHistoryTool(facts: factProvider),
        ]
        rebuildSession(withDigest: nil)
    }

    func prewarm() {
        session?.prewarm()
    }

    // MARK: - Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        guard availability.isAvailable, factProvider != nil, session != nil else {
            appendFailed(text: "ai_coach.chat.unavailable".localized)
            return
        }

        messages.append(CoachChatMessage(role: .user, text: trimmed, phase: .final))
        turnTopics.append(topic(for: trimmed))

        let assistant = CoachChatMessage(role: .assistant, text: "", phase: .streaming)
        messages.append(assistant)
        isResponding = true

        let assistantId = assistant.id
        streamTask = Task {
            await self.performTurn(prompt: trimmed, assistantId: assistantId)
            self.isResponding = false
            self.streamTask = nil
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.phase == .streaming }) {
            if messages[idx].text.isEmpty {
                messages.remove(at: idx)
            } else {
                messages[idx].phase = .final
            }
        }
        isResponding = false
    }

    func reset() {
        cancel()
        messages.removeAll()
        turnTopics.removeAll()
        rebuildSession(withDigest: nil)
        session?.prewarm()
    }

    // MARK: - Turn execution

    private func performTurn(prompt: String, assistantId: UUID) async {
        var didCondenseRetry = false

        while true {
            await condenseIfNeeded()
            guard let session else { markFailed(assistantId); return }

            // Reset the assistant bubble for each attempt (a retry after overflow
            // must not keep partial text from the failed attempt).
            updateAssistant(assistantId) { $0.text = ""; $0.phase = .streaming }

            do {
                let options = GenerationOptions(maximumResponseTokens: Self.maxResponseTokens)
                let stream = session.streamResponse(to: prompt, options: options)
                for try await snapshot in stream {
                    if Task.isCancelled { return }
                    updateAssistant(assistantId) { $0.text = Self.stripMarkdown(snapshot.content) }
                }
                if Task.isCancelled { return }
                updateAssistant(assistantId) { $0.phase = .final }
                return
            } catch {
                if Task.isCancelled { return }
                if isContextOverflow(error), !didCondenseRetry {
                    didCondenseRetry = true
                    logger.notice("chat context overflow — condensing and retrying once")
                    condense()
                    continue
                }
                logError(error)
                markFailed(assistantId)
                return
            }
        }
    }

    // MARK: - Overflow handling

    /// Proactive: condense before sending if the transcript + tools approach the
    /// context budget. On 26.4+ this is token-accurate; below, a chars/3.5
    /// estimate with a conservative reserve.
    private func condenseIfNeeded() async {
        guard let session else { return }
        let contextSize = SystemLanguageModel.default.contextSize

        var used = ChatOverflowPolicy.estimatedTokens(messages: messages)
        if #available(iOS 26.4, *) {
            let entries = Array(session.transcript)
            if let transcriptTokens = try? await SystemLanguageModel.default.tokenCount(for: entries) {
                used = transcriptTokens
                if let toolTokens = try? await SystemLanguageModel.default.tokenCount(for: tools) {
                    used += toolTokens
                }
            }
        }

        if ChatOverflowPolicy.shouldCondense(usedTokens: used, contextSize: contextSize) {
            logger.notice("chat proactively condensing (used=\(used), contextSize=\(contextSize))")
            condense()
        }
    }

    /// Rebuilds the session with a Swift-side digest of the conversation so far.
    /// The visible `messages` array is untouched — only the model's working set
    /// shrinks. Prewarms the fresh session so the pending send starts fast.
    private func condense() {
        rebuildSession(withDigest: ChatOverflowPolicy.digest(messages: messages, turnTopics: turnTopics))
        session?.prewarm()
    }

    // MARK: - Helpers

    private func rebuildSession(withDigest digest: String?) {
        let instructions = CoachChatInstructions.build(digest: digest)
        session = LanguageModelSession(tools: tools, instructions: Instructions(instructions))
    }

    private func isContextOverflow(_ error: Error) -> Bool {
        guard let generation = error as? LanguageModelSession.GenerationError else { return false }
        if case .exceededContextWindowSize = generation { return true }
        return false
    }

    /// Strips the Markdown emphasis markers the on-device model sometimes emits
    /// (`**bold**`, `__x__`, `` `code` ``) — the chat renders plain `Text`, so the
    /// raw markers would show as literal characters. Belt-and-suspenders alongside
    /// the "plain text only" instruction. Cumulative snapshots mean a marker is
    /// stripped whole once generated; a lone `*` mid-stream is rare and transient.
    static func stripMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    private func topic(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 40 ? trimmed : String(trimmed.prefix(40)) + "…"
    }

    private func updateAssistant(_ id: UUID, _ mutate: (inout CoachChatMessage) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[idx])
    }

    private func markFailed(_ id: UUID) {
        updateAssistant(id) { message in
            if message.text.isEmpty { message.text = "ai_coach.chat.error.generic".localized }
            message.phase = .failed
        }
    }

    private func appendFailed(text: String) {
        messages.append(CoachChatMessage(role: .assistant, text: text, phase: .failed))
    }

    private func logError(_ error: Error) {
        guard let generation = error as? LanguageModelSession.GenerationError else {
            logger.error("chat generation failed: \(String(describing: type(of: error)), privacy: .public)")
            return
        }
        switch generation {
        case .guardrailViolation:
            logger.warning("chat guardrail violation")
        case .exceededContextWindowSize:
            logger.error("chat context window exceeded after condense+retry")
        case .rateLimited:
            logger.notice("chat rate limited")
        case .unsupportedLanguageOrLocale:
            logger.error("chat unsupported locale")
        default:
            logger.error("chat generation error: \(String(describing: generation), privacy: .public)")
        }
    }
}
