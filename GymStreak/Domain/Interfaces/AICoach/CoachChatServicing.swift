//
//  CoachChatServicing.swift
//  GymStreak
//
//  Protocol surface for the chat assistant service. Documents the API the
//  `CoachChatViewModel` drives. Note: the ViewModel references the concrete
//  `CoachChatService` for SwiftUI Observation (nested `@Observable` reads don't
//  propagate through an existential), so this protocol is a documentation/parity
//  contract rather than the injection seam — mirroring how `AICoachAvailability`
//  is deliberately consumed concretely (see docs/ai-coach.md).
//

import Foundation

/// The session-holding chat service surface.
@MainActor
protocol CoachChatServicing: AnyObject {

    /// The visible conversation. Never shrinks due to transcript condensation.
    var messages: [CoachChatMessage] { get }

    /// `true` while an assistant turn is streaming.
    var isResponding: Bool { get }

    /// Provides the tool-backing data layer and builds the tool-equipped session.
    /// Idempotent — the first call wins; later calls are ignored (the underlying
    /// `ModelContext` is the app's stable main context).
    func configure(factProvider: ChatFactProviding)

    /// Warms the model weights so the first token arrives faster.
    func prewarm()

    /// Appends the user message and streams the assistant reply.
    func send(_ text: String)

    /// Cancels the in-flight assistant turn, if any.
    func cancel()

    /// Clears the conversation and starts a fresh session.
    func reset()
}
