//
//  CoachChatViewModel.swift
//  GymStreak
//
//  Drives `CoachChatView`. Holds the input field + suggested questions and
//  forwards the message list / responding state from the session-holding
//  `CoachChatService` (a singleton, so the conversation survives navigation).
//  Since ticket 08 it also meters sending against the free monthly taster
//  (docs/pro-subscription.md §5e).
//
//  The service is referenced concretely (not through `CoachChatServicing`)
//  because SwiftUI Observation cannot see `@Observable` reads through an
//  existential — the same deliberate concrete-reference choice made for
//  `AICoachAvailability` (see docs/ai-coach.md).
//

import Foundation

/// The §8 placement D hint for the chat's monthly allowance: finished copy plus
/// the two numbers the meter draws. Mirrors `RoutineCapNudge`.
struct CoachChatAllowanceNudge: Equatable {
    let text: String
    let used: Int
    let limit: Int
}

@Observable
@MainActor
final class CoachChatViewModel {

    // MARK: - Input state

    var inputText: String = ""

    // MARK: - Dependencies

    private let service: CoachChatService
    private let availability: AICoachAvailabilityProviding
    private let screenContext: CoachScreenContext
    private let allowanceGate: AICoachAllowanceGate

    /// `onAppear` fires again every time the pushed AI-coach settings screen is
    /// popped back to the chat, and returning from settings is not the "opened
    /// Coach Chat at 0 remaining" intent §8 C gates on. One raise per
    /// presentation: this ViewModel is `@State` inside the cover's content, so
    /// it is rebuilt the next time the chat is opened.
    private var didRaiseOpenPaywall = false

    /// Dependencies default to the shared instances *inside* the initializer
    /// body rather than as `= Foo.shared` default arguments: a default argument
    /// is evaluated in the caller's isolation, so referencing a `@MainActor`
    /// singleton there is rejected outside the main actor. Resolving `nil` in
    /// this `@MainActor` init body is the pattern every other AI-coach ViewModel
    /// uses (`PeriodRecapViewModel`, `ExerciseDeepDiveViewModel`,
    /// `PostWorkoutRecapViewModel`, `WorkoutAnalysisViewModel`).
    ///
    /// `allowanceGate` has no such default: it carries the entitlement and the
    /// paywall seam, which per Hard rule 2 come from `AppDependencies` and never
    /// from a singleton.
    init(
        allowanceGate: AICoachAllowanceGate,
        service: CoachChatService? = nil,
        availability: AICoachAvailabilityProviding? = nil,
        screenContext: CoachScreenContext? = nil
    ) {
        self.allowanceGate = allowanceGate
        self.service = service ?? .shared
        self.availability = availability ?? AICoachAvailability.shared
        self.screenContext = screenContext ?? .shared
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

    // MARK: - Free-tier allowance

    /// The §8 placement D hint, or `nil` when none belongs on screen — which is
    /// every state but the last free message and none left.
    ///
    /// Computed rather than stored, so it tracks both the count and the
    /// entitlement: the gate reads the `@Observable` entitlement provider here,
    /// during the chat's `body` evaluation, which is what makes a purchase or a
    /// lapse remove or restore the hint with no reload. The count itself
    /// refreshes because sending changes `messages`, and this body already reads
    /// that.
    var allowanceNudge: CoachChatAllowanceNudge? {
        switch allowanceGate.nudgeState {
        case .lastRemaining(let consumed, let limit):
            return CoachChatAllowanceNudge(
                text: String(
                    format: "ai_coach.chat.allowance.nudge".localized,
                    AIAllowancePolicy.remaining(consumed: consumed, limit: limit),
                    limit
                ),
                used: consumed,
                limit: limit
            )
        case .exhausted(let consumed, let limit):
            return CoachChatAllowanceNudge(
                text: "ai_coach.chat.allowance.nudge.exhausted".localized,
                used: consumed,
                limit: limit
            )
        case nil:
            return nil
        }
    }

    // MARK: - Lifecycle

    /// Wires the tool-backing data layer (idempotent) and warms the model.
    ///
    /// Takes a *factory* rather than a built provider so the provider is constructed
    /// only when the service is still unconfigured. `configure` is idempotent and would
    /// discard a second one, but building it is no longer free: since audit P1.3 it
    /// spins up a `@ModelActor` and its `ModelContext`, and the chat is a
    /// `fullScreenCover`, so this runs on every presentation. The factory comes from
    /// `AppDependencies` — Presentation never names the concrete Data type.
    ///
    /// Restoring and reading the existing conversation happens here unconditionally:
    /// a user's own chat history is never gated and never costs an allowance
    /// (§7 Rule 4). Only the paywall for an *exhausted* allowance is raised.
    func onAppear(makeFactProvider: () -> ChatFactProviding) {
        if !service.isConfigured {
            service.configure(factProvider: makeFactProvider())
        }
        service.prewarm()
        if !didRaiseOpenPaywall {
            didRaiseOpenPaywall = true
            allowanceGate.presentPaywallIfExhausted()
        }
    }

    // MARK: - Actions

    func send() {
        let text = inputText
        guard startTurn(with: text) else { return }
        inputText = ""
    }

    func send(suggestion: String) {
        guard startTurn(with: suggestion) else { return }
        inputText = ""
    }

    /// Reserves a taster unit, starts the turn, and gives the unit back if the
    /// turn never started or failed. Returns `false` when the paywall was raised
    /// instead — the input text is then kept, so the user does not lose what
    /// they typed to a gate.
    private func startTurn(with text: String) -> Bool {
        guard let ticket = allowanceGate.requestGeneration() else { return false }
        // Captures the **gate**, not `self`. The dominant cancellation path is
        // the cover's `onDismiss` calling `CoachChatService.shared.cancel()`,
        // which runs after this `@State`-owned ViewModel is gone — a `[weak
        // self]` capture would be nil by then and quietly keep the unit for an
        // answer the user never saw. The gate holds only app-lifetime
        // collaborators, so a strong capture neither leaks nor cycles.
        let didStart = service.send(text) { [gate = allowanceGate] outcome in
            guard outcome == .failed else { return }
            gate.refund(ticket)
        }
        guard didStart else {
            allowanceGate.refund(ticket)
            return false
        }
        return true
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
