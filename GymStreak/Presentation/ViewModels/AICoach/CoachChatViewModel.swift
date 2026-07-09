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

    init(
        service: CoachChatService = .shared,
        availability: AICoachAvailabilityProviding = AICoachAvailability.shared
    ) {
        self.service = service
        self.availability = availability
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
    let suggestedQuestions: [String] = [
        "ai_coach.chat.suggestion.next_workout".localized,
        "ai_coach.chat.suggestion.pr".localized,
        "ai_coach.chat.suggestion.this_week".localized,
    ]

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
}
