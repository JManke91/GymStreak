//
//  RoutineDraftService.swift
//  GymStreak
//
//  The routine-drafting service: a fresh `LanguageModelSession` per model turn, its
//  instructions, and the mapping from a guided-generation snapshot to the plain values
//  the rest of the app works in. See docs/ai-coach-routine-drafting.md.
//
//  **Its own session, not a card in the chat transcript.** The chat's context window is
//  shared by its instructions, all three tool schemas and the whole transcript, and
//  `CoachChatMessage` is a persisted `{id, role, text, phase}` that a structured draft
//  payload does not fit. A separate session also keeps this feature's generation
//  independent of the chat's per-message meter.
//
//  **A guided draft is not one continuing session** (ticket 04). Every turn — the
//  description, then each answer to a question Swift decided to ask — is sent to a fresh
//  session as the person's words alone. On device (2026-09-24) a continued session
//  answered "Bankdrücken und Kniebeugen" with a new list of invented categories: with its
//  own earlier invented reply in the transcript, the model reproduced that shape instead
//  of transcribing. A fresh session never sees anything the model wrote, and it cannot
//  overflow the context window, so no condense policy is needed.
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

    /// Greedy: this is transcription, not writing, so the most likely token is the right
    /// one — and the same description then drafts the same routine every time, which makes
    /// a device round reproducible. Measured on the macOS 27 on-device model (2026-09-27):
    /// equal or better than default sampling on every probed description, and the routine
    /// name stopped flipping between runs. Apple recommends greedy "for consistent output".
    private static var generationOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maximumResponseTokens)
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "RoutineDraft")
    private let availability: AICoachAvailabilityProviding

    /// A session `prewarm()` warmed and no turn has used yet, with the unit its
    /// instructions state. The next turn takes it; every later turn builds its own.
    /// **Registers no `Tool`s** — structured generation only.
    private var warmSession: LanguageModelSession?
    private var warmUnit: WeightUnit?
    /// What the person has said in this drafting conversation, oldest first: the
    /// description, then each answer framed with the question it answers. A line joins
    /// once its turn has finished, so a thrown or cancelled turn is not repeated. An answer
    /// whose finished draft the ViewModel refuses (no exercise survived) *does* stay — it
    /// is still the person's own words, and a retry is sent alongside it.
    private var turns: [String] = []

    init(availability: AICoachAvailabilityProviding? = nil) {
        self.availability = availability ?? AICoachAvailability.shared
    }

    // MARK: - RoutineDrafting

    func prewarm() {
        guard availability.isAvailable, warmSession == nil else { return }
        let unit = warmUnit ?? .kilograms
        let session = Self.makeSession(unit: unit)
        warmSession = session
        warmUnit = unit
        session.prewarm()
    }

    func draft(
        from description: String,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        turns = []
        return respond(adding: description, weightUnit: weightUnit)
    }

    func answer(
        _ answer: String,
        to gap: RoutineDraftGap,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        respond(adding: RoutineDraftInstructions.answer(answer, to: gap), weightUnit: weightUnit)
    }

    // MARK: - Turn

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Streams one turn: every line the person has said so far plus `line`, sent to a
    /// session of its own.
    private func respond(
        adding line: String,
        weightUnit: WeightUnit
    ) -> AsyncThrowingStream<RoutineDraftSnapshot, Error> {
        let lines = turns + [line]
        let firstSession = takeSession(unit: weightUnit)
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let start = ContinuousClock.now
                // Time to the first snapshot and to the finished draft, in milliseconds —
                // what docs/ai-coach-routine-drafting-eval.md records as latency.
                var firstSnapshot: Duration?
                // The plain prompt first, then — only when Apple's guardrail declines it
                // before anything was generated — the same words reframed, once, in a
                // session of its own. See `RoutineDraftInstructions.reframedPrompt`.
                let prompts = [
                    RoutineDraftInstructions.prompt(from: lines),
                    RoutineDraftInstructions.reframedPrompt(from: lines),
                ]
                for (attempt, prompt) in prompts.enumerated() {
                    let session = attempt == 0 ? firstSession : Self.makeSession(unit: weightUnit)
                    do {
                        let stream = session.streamResponse(
                            to: prompt,
                            generating: RoutineDraftOutput.self,
                            options: Self.generationOptions
                        )
                        for try await snapshot in stream {
                            try Task.checkCancellation()
                            if firstSnapshot == nil { firstSnapshot = ContinuousClock.now - start }
                            continuation.yield(Self.snapshot(from: snapshot.content))
                        }
                        try Task.checkCancellation()
                        self.turns.append(line)
                        let first = Self.milliseconds(firstSnapshot ?? .zero)
                        let total = Self.milliseconds(ContinuousClock.now - start)
                        self.logger.notice("routine draft turn \(self.turns.count) first snapshot \(first) ms, finished \(total) ms, attempt \(attempt + 1)")
                        continuation.finish()
                        return
                    } catch {
                        self.log(error)
                        let isDeclined = Self.isDeclinedByModel(error)
                        if isDeclined, firstSnapshot == nil, attempt + 1 < prompts.count, !Task.isCancelled {
                            continue
                        }
                        continuation.finish(throwing: isDeclined ? RoutineDraftingError.declinedByModel : error)
                        return
                    }
                }
            }
            // Cancelling the consuming task terminates the stream, which has to reach
            // the generation itself — otherwise a dismissed sheet leaves the model
            // running for an answer nobody will see.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Session

    /// The prewarmed session when it states the right unit, else a new one. Never
    /// prewarms here: a respond call follows immediately, and `prewarm()` needs ≥1 s
    /// before one to help (the chat's post-condense failures came from exactly that).
    private func takeSession(unit: WeightUnit) -> LanguageModelSession {
        defer { warmSession = nil }
        if let warmSession, warmUnit == unit { return warmSession }
        warmUnit = unit
        return Self.makeSession(unit: unit)
    }

    private static func makeSession(unit: WeightUnit) -> LanguageModelSession {
        LanguageModelSession(instructions: Instructions(RoutineDraftInstructions.build(unit: unit)))
    }

    // MARK: - Snapshot mapping

    /// Maps one cumulative guided-generation snapshot into the plain value type.
    ///
    /// **Only fully generated exercises come through.** In a partial snapshot every
    /// property is Optional, and an exercise name arrives token by token — grounding a
    /// half-written name would resolve it against the library on every snapshot and walk
    /// the row through whatever the prefixes happen to match before it settles. An entry
    /// joins the draft once every one of its fields is present.
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
              let weight = partial.weight,
              let repRange = partial.repRange,
              let restUnit = partial.restUnit,
              let restAmount = partial.restAmount
        else { return nil }
        return RoutineDraftEntry(
            name: name,
            setCount: setCount,
            reps: reps,
            weight: weight,
            repRange: repRange,
            restUnit: restUnit.entryUnit,
            restAmount: restAmount
        )
    }

    // MARK: - Errors

    /// Whether the model declined the words themselves — its guardrail fired or it refused.
    ///
    /// Matched **by case, never by `NSError.code`**: on iOS 27 these arrive as
    /// `LanguageModelError`, whose web-documented case order disagrees with the shipped
    /// SDK's (`guardrailViolation` is third in the 27.0 SDK), and a guess from the code
    /// number was wrong on device (2026-09-25). iOS 26 throws the older `GenerationError`.
    private static func isDeclinedByModel(_ error: Error) -> Bool {
        if #available(iOS 27.0, *), let modelError = error as? LanguageModelError {
            switch modelError {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        return false
    }

    // MARK: - Logging

    /// The iOS 27 error's case name, for a public log line — never its payload.
    private static func caseLabel(_ error: Error) -> String {
        guard #available(iOS 27.0, *), let modelError = error as? LanguageModelError else {
            return "other"
        }
        switch modelError {
        case .contextSizeExceeded: return "contextSizeExceeded"
        case .rateLimited: return "rateLimited"
        case .guardrailViolation: return "guardrailViolation"
        case .refusal: return "refusal"
        case .unsupportedCapability: return "unsupportedCapability"
        case .unsupportedTranscriptContent: return "unsupportedTranscriptContent"
        case .unsupportedGenerationGuide: return "unsupportedGenerationGuide"
        case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
        case .timeout: return "timeout"
        @unknown default: return "unknown"
        }
    }

    private func log(_ error: Error) {
        if error is CancellationError { return }
        guard let generation = error as? LanguageModelSession.GenerationError else {
            // A bare NSError code is only the case's position in an enum whose documented
            // order disagrees with the shipped SDK (device, 2026-09-25: code 3 said nothing),
            // so the case is named. The description stays private: a refusal or guardrail
            // payload can carry the person's own words. Xcode shows it with a debugger attached.
            let ns = error as NSError
            logger.error("routine draft failed: \(Self.caseLabel(error), privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code) error=\(String(describing: error), privacy: .private)")
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

private extension RoutineDraftRestUnit {
    var entryUnit: RoutineDraftEntry.RestUnit {
        switch self {
        case .unstated: .unstated
        case .seconds: .seconds
        case .minutes: .minutes
        }
    }
}
