//
//  RoutineDraftViewModel.swift
//  GymStreak
//
//  Drives the routine-drafting sheet: preflight, the drafting session, the grounding
//  pass, and the one call that writes. See docs/ai-coach-routine-drafting.md.
//
//  It holds no FoundationModels type. `RoutineDrafting` hands it plain
//  `RoutineDraftSnapshot` values, which is what makes the acceptance criteria about the
//  allowance unit assertable without an on-device model.
//

import Foundation

@Observable
@MainActor
final class RoutineDraftViewModel {

    // MARK: - Nested types

    /// Where the sheet is. Deliberately four states and not a state machine over the
    /// draft itself: the draft is a separate `private(set)` payload because it keeps
    /// growing *during* `.drafting`, and a phase that carried it would change identity on
    /// every snapshot.
    enum Phase: Equatable {
        /// Typing the description. Also where a cancelled or discarded draft returns to.
        case describing
        /// A generation is running; `rows` fills as exercises complete.
        case drafting
        /// The draft is final and on screen — including the case where nothing in it
        /// could be resolved, which the sheet explains rather than hides.
        case review
        case failed(String)
    }

    /// One row of the review list: a value struct, never a `GroundedDraftExercise`.
    ///
    /// The row's `name` is the **library exercise's own name**, not the model's spelling
    /// of it, and its `summary` is a finished string. A row view that held the drafted
    /// exercise would read an `@Model` property — and format a weight — once per row per
    /// render (CLAUDE.md § "Performance: main thread and rendering", rules 2 and 4).
    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        let summary: String
    }

    // MARK: - Input state

    var descriptionText: String = ""

    // MARK: - Observable state

    private(set) var phase: Phase = .describing
    /// The routine's name as drafted, or empty until the model has written one.
    private(set) var routineName: String = ""
    private(set) var rows: [Row] = []
    /// Names the live library could not place. Never silently empty — see
    /// `GroundedRoutineDraft`.
    private(set) var unmatchedNames: [String] = []
    /// The same names as one finished line. Joined here rather than in the sheet's
    /// `body`: a collection operation in a `body` is a collection operation in a `body`,
    /// however short the collection is.
    private(set) var unmatchedSummary: String = ""
    /// Flips once, when a routine has actually been written. The sheet dismisses on it.
    private(set) var didCreateRoutine = false

    // MARK: - Dependencies

    private let allowanceGate: AICoachAllowanceGate
    private let drafting: any RoutineDrafting
    private let exerciseRepository: ExerciseRepository
    private let routines: any RoutineCreating
    private let paywalls: any PaywallPresenting
    private let availability: any AICoachAvailabilityProviding
    /// Rebuilt with the library it grounds against — its resolution memo is keyed by name
    /// alone, so it must not outlive the `[Exercise]` it was used with.
    private var grounder = RoutineDraftGrounder()

    // MARK: - Private state

    /// Fetched once per drafting session, **on the chip tap rather than in the sheet's
    /// `onAppear`**: it is a synchronous full-library SwiftData fetch, and `onAppear`
    /// runs while the sheet is animating in (CLAUDE.md rendering rule 7). Grounding then
    /// runs against this array on every streamed snapshot, so a repository fetch there
    /// would be a store round-trip per token burst.
    private var library: [Exercise] = []
    private var weightUnit: WeightUnit = .kilograms
    private var draft: GroundedRoutineDraft?
    private var streamTask: Task<Void, Never>?

    /// The allowance unit this **drafting session** reserved — one, for the session, not
    /// one per message. A guided conversation (ticket 04) must never cost a free user
    /// their whole month for a single routine.
    private var ticket: AICoachAllowanceGate.Ticket?
    /// Whether the reserved unit is still owed back. Cleared the moment a draft the
    /// person can act on is on screen: they got what the unit paid for, whether or not
    /// they go on to create the routine. Kept separate from `ticket` because the ticket
    /// itself survives a successful draft — that is what makes ticket 04's follow-up
    /// message cost nothing more.
    private var isTicketRefundable = false

    // MARK: - Init

    /// Dependencies are resolved from `AppDependencies`, never from singletons: the
    /// entitlement, the paywall seam and the creation seam all come from the composition
    /// root (Hard rule 2). `availability` defaults inside the `@MainActor` init body for
    /// the reason every AI-coach ViewModel does — a `= Foo.shared` default argument is
    /// evaluated in the caller's isolation.
    init(
        allowanceGate: AICoachAllowanceGate,
        drafting: any RoutineDrafting,
        exerciseRepository: ExerciseRepository,
        routines: any RoutineCreating,
        paywalls: any PaywallPresenting,
        availability: (any AICoachAvailabilityProviding)? = nil
    ) {
        self.allowanceGate = allowanceGate
        self.drafting = drafting
        self.exerciseRepository = exerciseRepository
        self.routines = routines
        self.paywalls = paywalls
        self.availability = availability ?? AICoachAvailability.shared
    }

    // MARK: - Derived state

    var isAvailable: Bool { availability.isAvailable }

    var isDrafting: Bool { phase == .drafting }

    var canSubmit: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDrafting
    }

    /// `true` only when there is something a Create button could actually write.
    var canCreate: Bool { phase == .review && !rows.isEmpty }

    /// The §8 placement D hint for the shared Coach allowance, or `nil` when none
    /// belongs on screen — which only ever means this reader is unmetered.
    ///
    /// Computed, not stored, so it tracks the entitlement as well as the count: the gate
    /// reads the `@Observable` entitlement provider here, during the sheet's `body`.
    var allowanceNudge: AIAllowanceNudge? {
        AIAllowanceNudge(
            state: allowanceGate.nudgeState,
            remainingFormat: "ai_coach.routine_draft.allowance.nudge".localized,
            exhaustedText: "ai_coach.routine_draft.allowance.nudge.exhausted".localized
        )
    }

    // MARK: - Preflight

    /// Whether the drafting sheet may open at all — **availability first, then the
    /// routine cap**, and no allowance is touched by either.
    ///
    /// The order is the whole point. A device that cannot run Apple Intelligence must
    /// never be shown a paywall for it: unavailable is a disappointment, not a conversion
    /// opportunity. And the cap has to fire *before* a person invests a description in a
    /// routine that could not be saved — the same reasoning the Create-Routine entry
    /// point already follows.
    ///
    /// - Returns: `false` when the sheet must not open. The paywall, if one belongs, has
    ///   already been raised.
    func requestDrafting() -> Bool {
        guard availability.isAvailable else { return false }
        guard !routines.isRoutineCapReached else {
            paywalls.present(.routineCap)
            return false
        }
        // Loaded here, before the sheet exists, so the fetch is not on the presentation
        // animation's critical path. Only on a preflight that actually opens the sheet:
        // a refused tap reads nothing.
        loadLibrary()
        return true
    }

    /// Loads the library the grounding pass matches against and warms the model.
    ///
    /// - Parameter weightUnit: the reader's unit, read from `\.weightUnit` by the sheet.
    ///   It reaches the instructions and is the unit every drafted weight comes back in.
    func onAppear(weightUnit: WeightUnit) {
        self.weightUnit = weightUnit
        // Normally a no-op: `requestDrafting()` loaded the library before this sheet was
        // presented. Kept as a fallback so a presentation that somehow bypassed the
        // preflight grounds against a real library instead of matching nothing.
        if library.isEmpty { loadLibrary() }
        drafting.prewarm()
    }

    private func loadLibrary() {
        library = exerciseRepository.fetchAll()
        // A fresh grounder with the library it will resolve against — see its `resolutions`.
        grounder = RoutineDraftGrounder()
    }

    // MARK: - Drafting

    /// Reserves the session's allowance unit and starts a draft.
    ///
    /// When the gate refuses, the paywall is raised and the typed description is kept —
    /// nobody loses what they wrote to a gate.
    func submit() {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isDrafting else { return }
        guard reserveAllowanceUnit() else { return }

        clearDraft()
        phase = .drafting
        let unit = weightUnit
        streamTask = Task { [weak self] in
            await self?.runDraft(text, weightUnit: unit)
        }
    }

    /// Stops an in-flight draft and gives the unit back. Writes nothing, by construction:
    /// nothing is written anywhere until `createRoutine()`.
    func cancelDrafting() {
        streamTask?.cancel()
        streamTask = nil
        refundReservedUnit()
        clearDraft()
        phase = .describing
    }

    private func runDraft(_ text: String, weightUnit unit: WeightUnit) async {
        do {
            for try await snapshot in drafting.draft(from: text, weightUnit: unit) {
                if Task.isCancelled { return }
                apply(snapshot)
            }
            if Task.isCancelled { return }
            finishDrafting()
        } catch {
            // A cancelled stream is reported by `cancelDrafting()`, which has already
            // refunded and reset — it must not also land here as a failure the person
            // sees.
            if Task.isCancelled || error is CancellationError { return }
            refundReservedUnit()
            phase = .failed("ai_coach.routine_draft.error".localized)
        }
    }

    /// Grounds one snapshot and republishes the review list.
    ///
    /// Grounding runs per snapshot rather than once at the end so the list fills with the
    /// **library's** names as exercises complete, instead of with the model's spelling of
    /// them corrected afterwards.
    private func apply(_ snapshot: RoutineDraftSnapshot) {
        let grounded = grounder.ground(snapshot, library: library, weightUnit: weightUnit)
        draft = grounded
        routineName = grounded.name
        unmatchedNames = grounded.unmatchedNames
        unmatchedSummary = grounded.unmatchedNames.joined(separator: ", ")
        rows = grounded.exercises.map {
            Row(id: $0.id, name: $0.exercise.name, summary: summary(for: $0))
        }
    }

    private func finishDrafting() {
        streamTask = nil
        phase = .review
        // A draft the app may not write is a drafting session that gave the person
        // nothing — the generation succeeded, the outcome did not. The unit goes back and
        // the sheet says what was left out.
        guard let draft, !draft.hasNothingToCreate else {
            refundReservedUnit()
            return
        }
        isTicketRefundable = false
    }

    // MARK: - Persisting

    /// Writes the draft through the one creation transaction this app has.
    ///
    /// `RoutinesViewModel.createRoutine(name:pendingExercises:)` materializes the routine,
    /// its exercises and their sets together, saves, and re-fetches — and that re-fetch is
    /// what syncs the new routine to the watch. There is no extra call to make here, and
    /// no second write path to maintain.
    func createRoutine() {
        guard let draft, !draft.hasNothingToCreate else { return }
        let name = draft.name.isEmpty
            ? "ai_coach.routine_draft.default_name".localized
            : draft.name
        routines.createRoutine(name: name, pendingExercises: draft.pendingExercises())
        didCreateRoutine = true
    }

    /// Throws the draft away. Nothing was ever written, so there is nothing to undo.
    func discard() {
        cancelDrafting()
    }

    /// Ends the drafting session, whatever ended it — Create, Discard, or the sheet being
    /// swiped away mid-stream. Cancels any generation still running, gives back a unit
    /// that bought nothing, and returns the sheet to a clean state for the next open.
    func sheetWasDismissed() {
        streamTask?.cancel()
        streamTask = nil
        refundReservedUnit()
        ticket = nil
        descriptionText = ""
        didCreateRoutine = false
        clearDraft()
        phase = .describing
        // Dropped so the next drafting session grounds against a freshly fetched library
        // rather than one that predates an exercise the person has since added.
        library = []
    }

    // MARK: - Allowance

    /// One unit per drafting session. A session that already holds one reserves nothing
    /// further, which is what keeps ticket 04's follow-up messages free.
    private func reserveAllowanceUnit() -> Bool {
        if ticket != nil { return true }
        guard let reserved = allowanceGate.requestGeneration() else { return false }
        ticket = reserved
        isTicketRefundable = true
        return true
    }

    /// Gives the session's unit back, if it is still owed. A no-op once a usable draft has
    /// landed, and a no-op for an unmetered reader — the gate decides that from the
    /// ticket, so an unmetered request can never be refunded into a free unit.
    private func refundReservedUnit() {
        guard isTicketRefundable, let ticket else { return }
        allowanceGate.refund(ticket)
        self.ticket = nil
        isTicketRefundable = false
    }

    // MARK: - Helpers

    private func clearDraft() {
        draft = nil
        routineName = ""
        rows = []
        unmatchedNames = []
        unmatchedSummary = ""
    }

    /// The row's finished subtitle, built here so no row view formats a weight.
    /// A drafted exercise with no load reads as sets and reps alone, which is what a
    /// bodyweight movement should say.
    private func summary(for drafted: GroundedDraftExercise) -> String {
        var parts = [
            "routine.sets_count".localized(drafted.setCount),
            "set.reps".localized(drafted.reps),
        ]
        if drafted.weightKilograms > 0 {
            parts.append(WeightFormatting.label(drafted.weightKilograms, in: weightUnit))
        }
        return parts.joined(separator: " • ")
    }
}
