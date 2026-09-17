//
//  RoutineDraftService.swift
//  GymStreak
//
//  The routine-drafting session: one `LanguageModelSession` per drafting session, its
//  instructions, and the mapping from a guided-generation snapshot to the plain values
//  the rest of the app works in. See docs/ai-coach-routine-drafting.md.
//
//  **Its own session, not a card in the chat transcript.** The chat's context window is
//  shared by its instructions, all three tool schemas and the whole transcript, and
//  `CoachChatMessage` is a persisted `{id, role, text, phase}` that a structured draft
//  payload does not fit. A separate session also keeps this feature's generation
//  independent of the chat's per-message meter.
//
//  Verified shape (same SDK as `CoachChatService`): guided generation via
//  `streamResponse(to:generating:options:)`, snapshots are cumulative, and the stream
//  surfaces failures when it is *iterated* rather than when it is created.
//

import Foundation
import FoundationModels
import os

@MainActor
final class RoutineDraftService: RoutineDrafting {

    // MARK: - Tuning

    /// Output-token cap for one draft. A drafted routine is a name and a bounded list of
    /// short records, so this bounds a runaway generation without bounding a real one.
    private static let maximumResponseTokens = 700

    // MARK: - Private

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "RoutineDraft")
    private let availability: AICoachAvailabilityProviding

    /// Retained across turns so ticket 04's follow-up questions land in the same
    /// conversation. Rebuilt when the reader's unit changes, because the instructions
    /// state the unit as a rule the model drafts by and a live session carries the
    /// instructions it was born with (the same reason `CoachChatService` re-seeds).
    private var session: LanguageModelSession?
    private var sessionUnit: WeightUnit?

    init(availability: AICoachAvailabilityProviding? = nil) {
        self.availability = availability ?? AICoachAvailability.shared
    }

    // MARK: - RoutineDrafting

    func prewarm() {
        guard availability.isAvailable else { return }
        activeSession(for: sessionUnit ?? .kilograms).prewarm()
    }

    func draft(
        from description: String,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let start = ContinuousClock.now
                do {
                    let stream = self.activeSession(for: weightUnit).streamResponse(
                        to: description,
                        generating: RoutineDraftOutput.self,
                        options: GenerationOptions(maximumResponseTokens: Self.maximumResponseTokens)
                    )
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        continuation.yield(Self.snapshot(from: snapshot.content))
                    }
                    let elapsed = ContinuousClock.now - start
                    self.logger.notice("routine draft finished in \(Int(elapsed.components.seconds)) s")
                    continuation.finish()
                } catch {
                    self.log(error)
                    continuation.finish(throwing: error)
                }
            }
            // Cancelling the consuming task terminates the stream, which has to reach
            // the generation itself — otherwise a dismissed sheet leaves the model
            // running for an answer nobody will see.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Session

    private func activeSession(for unit: WeightUnit) -> LanguageModelSession {
        if let session, sessionUnit == unit { return session }
        let built = LanguageModelSession(
            instructions: Instructions(RoutineDraftInstructions.build(unit: unit))
        )
        session = built
        sessionUnit = unit
        return built
    }

    // MARK: - Snapshot mapping

    /// Maps one cumulative guided-generation snapshot into the plain value type.
    ///
    /// **Only fully generated exercises come through.** In a partial snapshot every
    /// property is Optional, and an exercise name arrives token by token — grounding a
    /// half-written name would resolve it against the library on every snapshot and walk
    /// the row through whatever the prefixes happen to match before it settles. An entry
    /// joins the draft once all four of its fields are present.
    private static func snapshot(from partial: RoutineDraftOutput.PartiallyGenerated) -> RoutineDraftSnapshot {
        RoutineDraftSnapshot(
            name: partial.routineName ?? "",
            exercises: (partial.exercises ?? []).compactMap(entry(from:))
        )
    }

    private static func entry(from partial: RoutineDraftExercise.PartiallyGenerated) -> RoutineDraftEntry? {
        guard let name = partial.name,
              let setCount = partial.setCount,
              let reps = partial.reps,
              let weight = partial.weight
        else { return nil }
        return RoutineDraftEntry(name: name, setCount: setCount, reps: reps, weight: weight)
    }

    // MARK: - Logging

    private func log(_ error: Error) {
        if error is CancellationError { return }
        guard let generation = error as? LanguageModelSession.GenerationError else {
            let ns = error as NSError
            logger.error("routine draft failed: domain=\(ns.domain, privacy: .public) code=\(ns.code)")
            return
        }
        switch generation {
        case .guardrailViolation:
            logger.warning("routine draft guardrail violation")
        case .decodingFailure:
            // The guided-generation-specific failure: the model's output could not be
            // deserialized into the schema, which Apple documents as also happening when
            // generation is terminated early. It reaches the person as the generic error
            // and refunds the unit, like any other failure.
            logger.error("routine draft could not be decoded into the draft schema")
        case .exceededContextWindowSize:
            logger.error("routine draft exceeded the context window")
        case .rateLimited:
            logger.notice("routine draft rate limited")
        case .unsupportedLanguageOrLocale:
            logger.error("routine draft unsupported locale")
        default:
            logger.error("routine draft error: \(String(describing: generation), privacy: .public)")
        }
    }
}
