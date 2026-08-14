//
//  CoachChatService.swift
//  GymStreak
//
//  Session-holding singleton for the chat assistant. Owns one retained
//  `LanguageModelSession` (multi-turn), the 3 tools, the visible message list,
//  and the automatic context-overflow handling (proactive digest condensation +
//  reactive retry). Survives navigation AND app termination: the finalized
//  conversation persists via `ChatConversationStore` (local-only JSON) and is
//  restored on `configure` — a fresh session then carries a digest of the
//  restored messages, the same mechanism condensation uses. Resets on an
//  explicit "New chat". See docs/ai-coach-chat-feasibility.md.
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
    private let store = ChatConversationStore()

    private var factProvider: ChatFactProviding?
    private var tools: [any Tool] = []
    private var session: LanguageModelSession?
    private var streamTask: Task<Void, Never>?

    /// One short topic per user turn (captured at send time), used to build the
    /// digest cheaply when the transcript is condensed. Deterministic — no extra
    /// inference. Indexed by turn, parallel to the user messages.
    private var turnTopics: [String] = []

    // MARK: - Configuration

    var isConfigured: Bool { factProvider != nil }

    func configure(factProvider: ChatFactProviding) {
        guard self.factProvider == nil else { return }
        self.factProvider = factProvider
        self.tools = [
            NextWorkoutTool(facts: factProvider),
            ExercisePRTool(facts: factProvider),
            WorkoutHistoryTool(facts: factProvider),
        ]

        // Restore the persisted conversation. The transcript is NOT restored —
        // the fresh session instead carries a digest of the restored messages
        // (the same mechanism condensation uses), so follow-ups keep grounding.
        if let snapshot = store.load(), !snapshot.messages.isEmpty {
            messages = snapshot.messages
            turnTopics = snapshot.turnTopics
            rebuildSession(withDigest: ChatOverflowPolicy.digest(messages: messages, turnTopics: turnTopics))
        } else {
            rebuildSession(withDigest: nil)
        }
    }

    func prewarm() {
        session?.prewarm()
    }

    // MARK: - Sending

    func send(_ text: String) {
        guard let turn = beginTurn(text) else { return }
        streamTask = Task {
            await self.performTurn(prompt: turn.prompt, assistantId: turn.assistantId)
            guard !Task.isCancelled else { return } // cancel() already cleaned up
            self.endTurn()
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
            store.save(messages: messages, turnTopics: turnTopics)
        }
        isResponding = false
    }

    func reset() {
        cancel()
        messages.removeAll()
        turnTopics.removeAll()
        store.clear()
        rebuildSession(withDigest: nil)
        session?.prewarm()
    }

    // MARK: - Turn lifecycle

    /// Validates the input and appends the user + streaming-assistant bubbles.
    /// Returns nil (turn not started) when empty, busy, or unavailable.
    private func beginTurn(_ text: String) -> (prompt: String, assistantId: UUID)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return nil }
        guard availability.isAvailable, factProvider != nil, session != nil else {
            appendFailed(text: "ai_coach.chat.unavailable".localized)
            return nil
        }

        messages.append(CoachChatMessage(role: .user, text: trimmed, phase: .final))
        turnTopics.append(topic(for: trimmed))

        let assistant = CoachChatMessage(role: .assistant, text: "", phase: .streaming)
        messages.append(assistant)
        isResponding = true
        return (trimmed, assistant.id)
    }

    /// Finishes a turn (success or failure) and persists the conversation.
    private func endTurn() {
        isResponding = false
        streamTask = nil
        store.save(messages: messages, turnTopics: turnTopics)
    }

    // MARK: - Turn execution

    private func performTurn(prompt: String, assistantId: UUID) async {
        var didCondenseRetry = false
        var didTransientRetry = false

        while true {
            await condenseIfNeeded()
            guard let session else { markFailed(assistantId); return }

            // Reset the assistant bubble for each attempt (a retry after overflow
            // must not keep partial text from the failed attempt).
            updateAssistant(assistantId) { $0.text = ""; $0.phase = .streaming }

            do {
                let options = GenerationOptions(maximumResponseTokens: Self.maxResponseTokens)
                let attemptStart = Date()
                var sawFirstToken = false
                let stream = session.streamResponse(to: prompt, options: options)
                for try await snapshot in stream {
                    if Task.isCancelled { return }
                    if !sawFirstToken, !snapshot.content.isEmpty {
                        sawFirstToken = true
                        let ms = Int(Date().timeIntervalSince(attemptStart) * 1000)
                        logger.notice("chat first token after \(ms) ms")
                    }
                    updateAssistant(assistantId) { $0.text = Self.stripMarkdown(snapshot.content) }
                }
                if Task.isCancelled { return }
                updateAssistant(assistantId) { $0.phase = .final }
                return
            } catch {
                if Task.isCancelled { return }
                if isContextOverflow(error) {
                    if !didCondenseRetry {
                        didCondenseRetry = true
                        logger.notice("chat context overflow — condensing and retrying once")
                        condense()
                        continue
                    }
                } else if !didTransientRetry {
                    // Opaque daemon-side failures (raw NSError, no first token)
                    // occurred on ~5% of Phase 0 drill turns and are transient —
                    // the same question succeeds on retry. Rebuild via the digest
                    // (a failed attempt may leave the session transcript wedged)
                    // and retry once before surfacing an error bubble.
                    didTransientRetry = true
                    logError(error)
                    logger.notice("chat transient generation failure — rebuilding session and retrying once")
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
    /// shrinks. Deliberately does NOT prewarm: a `streamResponse` follows
    /// immediately, and Apple documents `prewarm()` as safe only with ≥1 s before
    /// the next respond call (see docs/ai-coach-chat-plan.md, Phase 0 fixes).
    private func condense() {
        rebuildSession(withDigest: ChatOverflowPolicy.digest(messages: messages, turnTopics: turnTopics))
    }

#if DEBUG
    // MARK: - Phase 0 auto-drill (DEBUG only)

    /// True while the scripted Phase 0 drill is running (drives the debug button).
    private(set) var isDrillRunning = false

    /// Phase 0 prep (docs/ai-coach-chat-plan.md): fires the scripted turns
    /// sequentially so the device session is passive observation. Watch the
    /// `app.gymstreak.aicoach` log stream for `chat first token after … ms`,
    /// `chat proactively condensing`, and the `ChatTool` fact lines to compare
    /// against on-screen answers. Keep the chat screen open — leaving it
    /// cancels the in-flight turn and aborts the drill.
    func runPhaseZeroDrill() {
        guard !isDrillRunning, !isResponding, session != nil else { return }
        isDrillRunning = true
        Task {
            let prompts = Self.drillPrompts
            logger.notice("drill starting: \(prompts.count) turns")
            for (index, prompt) in prompts.enumerated() {
                logger.notice("drill turn \(index + 1)/\(prompts.count): \(prompt, privacy: .public)")
                guard let turn = beginTurn(prompt) else {
                    logger.error("drill turn \(index + 1) could not start — aborting drill")
                    break
                }
                let turnStart = Date()
                let turnTask = Task {
                    await self.performTurn(prompt: turn.prompt, assistantId: turn.assistantId)
                }
                streamTask = turnTask
                await turnTask.value
                if turnTask.isCancelled {
                    logger.notice("drill cancelled at turn \(index + 1)")
                    break
                }
                endTurn()
                let ms = Int(Date().timeIntervalSince(turnStart) * 1000)
                logger.notice("drill turn \(index + 1)/\(prompts.count) finished in \(ms) ms")
            }
            isDrillRunning = false
            logger.notice("drill finished")
        }
    }

    /// 40 scripted turns: EN/DE mix over all 3 tools, a guaranteed no-match name
    /// (times the model-assisted re-call path), small talk, and late repeats of
    /// PR/next-workout questions so post-condensation answers can be compared
    /// against the fact log.
    private static let drillPrompts: [String] = [
        "When is my next workout?",
        "What's my bench press PR?",
        "How many workouts did I do this week?",
        "Wann ist mein nächstes Workout?",
        "Was ist mein Bestwert beim Bankdrücken?",
        "Wie viele Workouts habe ich letzte Woche gemacht?",
        "What's on my plan this week?",
        "What is my squat PR?",
        "How many workouts did I complete this month?",
        "Was ist mein Rekord beim Kreuzheben?",
        "When was my last workout?",
        "How long is my current streak?",
        "What's my PR on lat pulldown?",
        "Wie sieht mein Plan für diese Woche aus?",
        "What's my deadlift record?",
        "How many workouts did I do last month?",
        "Was ist mein Bestwert beim Schulterdrücken?",
        "Which workout is due next?",
        "What's my PR on barbell row?",
        "Wie viele Trainings habe ich diesen Monat absolviert?",
        "What is my overhead press PR?",
        "Wann war mein letztes Training?",
        "How many workouts have I done in total?",
        "Was ist mein Bestwert beim Latziehen?",
        "Do you think I should train more often?",
        "What's my PR on cable fly?",
        "How many workouts this week so far?",
        "Wann ist mein nächstes Workout fällig?",
        "What's my PR on leg press?",
        "Wie ist meine aktuelle Serie?",
        "What's my PR on flurbelblatz?",
        "How many workouts did I do this week?",
        "What's my bench press PR?",
        "Wann ist mein nächstes Workout?",
        "Was ist mein Bestwert beim Bankdrücken?",
        "What was my most recent workout?",
        "How long is my streak?",
        "What's on my plan this week?",
        "Wie viele Workouts habe ich insgesamt gemacht?",
        "Was ist mein Rekord bei Kniebeugen?",
    ]
#endif

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
            // Framework errors that aren't GenerationError reach us as opaque
            // NSError (ObjC/daemon layer) — domain+code identify the culprit.
            let ns = error as NSError
            logger.error("chat generation failed: \(String(describing: type(of: error)), privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code) desc=\(ns.localizedDescription, privacy: .public)")
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
