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

    /// Whether `configure` has already installed a fact provider. Lets a caller skip
    /// *building* one — since audit P1.3 that allocates a `@ModelActor` and its
    /// `ModelContext`, so it should not happen on every appearance.
    var isConfigured: Bool { get }

    /// Provides the tool-backing data layer, restores the persisted conversation
    /// (if any), and builds the tool-equipped session — seeded with a digest of
    /// the restored messages so follow-ups keep grounding across launches.
    /// Idempotent — the first call wins; later calls are ignored (the provider owns
    /// a stable, app-lifetime read boundary).
    func configure(factProvider: ChatFactProviding)

    /// Warms the model weights so the first token arrives faster.
    func prewarm()

    /// Appends the user message and streams the assistant reply.
    func send(_ text: String)

    /// Cancels the in-flight assistant turn, if any.
    func cancel()

    /// Clears the conversation (including its persisted copy) and starts a
    /// fresh session.
    func reset()
}
