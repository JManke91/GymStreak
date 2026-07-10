//
//  CoachChatViewModel.swift
//  GymStreak
//
//  Drives `CoachChatView`. Holds the input field + suggested questions and
//  forwards the message list / responding state from the session-holding
//  `CoachChatService` (a singleton, so the conversation survives navigation).
//
//  The service is referenced concretely (not through `CoachChatServicing`)
//  because SwiftUI Observation cannot see `@Observable` reads through an
//  existential — the same deliberate concrete-reference choice made for
//  `AICoachAvailability` (see docs/ai-coach.md).
//

import Foundation
import SwiftData

@Observable
@MainActor
final class CoachChatViewModel {

    // MARK: - Input state

    var inputText: String = ""

    // MARK: - Dependencies

    private let service: CoachChatService
    private let availability: AICoachAvailabilityProviding
    private let screenContext: CoachScreenContext

    init(
        service: CoachChatService = .shared,
        availability: AICoachAvailabilityProviding = AICoachAvailability.shared,
        screenContext: CoachScreenContext = .shared
    ) {
        self.service = service
        self.availability = availability
        self.screenContext = screenContext
    }

    // MARK: - Forwarded state

    var messages: [CoachChatMessage] { service.messages }
    var isResponding: Bool { service.isResponding }
    var isAvailable: Bool { availability.isAvailable }
    var isEmptyConversation: Bool { service.messages.isEmpty }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    /// Tappable starter questions — each is one the 3 tools can actually answer,
    /// which doubles as a guarantee that first-touch queries land.
    ///
    /// When the chat was opened from a screen with an anchor entity
    /// (`CoachScreenContext`), the generic PR chip is replaced by an anchored
    /// one ("What's my PR on Bench Press?") — still grounded by `getExercisePR`.
    var suggestedQuestions: [String] {
        var questions = [
            "ai_coach.chat.suggestion.next_workout".localized,
            "ai_coach.chat.suggestion.pr".localized,
            "ai_coach.chat.suggestion.this_week".localized,
        ]
        if case .exercise(let name) = screenContext.presentedAnchor {
            questions[1] = String(
                format: "ai_coach.chat.suggestion.anchor_pr".localized,
                name
            )
        }
        return questions
    }

    // MARK: - Lifecycle

    /// Wires the tool-backing data layer (idempotent) and warms the model.
    func onAppear(modelContext: ModelContext) {
        service.configure(factProvider: ChatFactService(modelContext: modelContext))
        service.prewarm()
    }

    // MARK: - Actions

    func send() {
        let text = inputText
        inputText = ""
        service.send(text)
    }

    func send(suggestion: String) {
        inputText = ""
        service.send(suggestion)
    }

    func cancel() {
        service.cancel()
    }

    func reset() {
        inputText = ""
        service.reset()
    }

#if DEBUG
    // MARK: - Phase 0 auto-drill (DEBUG only)

    var isDrillRunning: Bool { service.isDrillRunning }

    func runPhaseZeroDrill() {
        service.runPhaseZeroDrill()
    }
#endif
}
