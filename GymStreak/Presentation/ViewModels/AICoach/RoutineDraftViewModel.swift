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

    /// Where the sheet is. Deliberately five states and not a state machine over the
    /// draft itself: the draft is a separate `private(set)` payload because it keeps
    /// growing *during* `.drafting`, and a phase that carried it would change identity on
    /// every snapshot.
    enum Phase: Equatable {
        /// Typing the description. Also where a cancelled or discarded draft returns to.
        case describing
        /// A generation is running; `rows` fills as exercises complete. Also a follow-up
        /// turn, during which the draft on screen stands until the new one is finished.
        case drafting
        /// The draft lacks something `GroundedRoutineDraft.gaps` can name, and the sheet
        /// is asking about it — one question at a time.
        case asking
        /// The draft is final and on screen — including the case where nothing in it
        /// could be resolved, which the sheet explains rather than hides.
        case review
        case failed(String)
    }

    /// The review list's row type. A top-level value struct in `RoutineDraftRows.swift`,
    /// alongside the composer that builds it.
    typealias Row = RoutineDraftRow

    // MARK: - Input state

    var descriptionText: String = ""
    /// The routine's name as drafted, or empty until the model has written one. Settable
    /// so the review sheet can rename it: the stream stops writing it once the draft is
    /// final, and Create writes whatever it holds then.
    var routineName: String = ""
    /// The person's answer to the current question.
    var answerText: String = ""

    // MARK: - Observable state

    private(set) var phase: Phase = .describing
    /// Every drafted exercise in the order it was described, resolved or not. An
    /// unresolved one stays in the list rather than being reported away from it — that is
    /// what makes it something the person can point at a library exercise.
    private(set) var rows: [Row] = []
    /// `true` while at least one row still has to be pointed at a library exercise or
    /// removed. The sheet turns it into the note saying those rows are left out of Create.
    private(set) var hasUnresolvedRows = false
    /// `true` when the draft holds at least one resolved exercise — something a Create
    /// could actually write. Stored rather than derived in the sheet's `body`: filtering a
    /// collection is filtering a collection, however short it is.
    private(set) var hasCreatableExercises = false
    /// What the confirmation shows, set once a routine has actually been written — the
    /// sheet swaps to its success face on it rather than closing silently.
    private(set) var createdRoutine: CreatedRoutineSummary?
    /// Set when a follow-up turn failed: the draft before it stands, and the person can
    /// answer again.
    private(set) var answerError: String?
    /// The names the grounding pass dropped because the person never said them, joined for
    /// the note under the list — or `nil`. Composed here, not in `body`.
    private(set) var droppedSummary: String?

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
    /// Rows the person reopened in `ConfigureExerciseSetsView`, keyed by drafted-row id —
    /// the value graph Create writes for them instead of the drafted scheme. Nothing here
    /// touches a `ModelContext` until `createRoutine()`.
    private var edits: [UUID: PendingRoutineExercise] = [:]
    private var streamTask: Task<Void, Never>?
    /// Which question the sheet is on, and which it already asked.
    private var conversation = RoutineDraftConversation()
    /// Everything the person typed in this conversation — the description and each answer
    /// sent to the model. A drafted exercise name must come from these words.
    private var personWords: [String] = []

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

    var isAsking: Bool { phase == .asking }

    /// The question on screen while `.asking`.
    var question: String? { conversation.question }

    var canSubmitAnswer: Bool {
        isAsking && !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the person may stop answering and review what is there — only when a
    /// Create could write something.
    var canReviewNow: Bool { isAsking && hasCreatableExercises }

    var didCreateRoutine: Bool { createdRoutine != nil }

    var canSubmit: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDrafting
    }

    /// `true` only when there is something a Create button could actually write —
    /// unresolved rows do not count, because they are exactly what Create leaves out.
    var canCreate: Bool { phase == .review && hasCreatableExercises }

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
        personWords = [text]
        phase = .drafting
        let unit = weightUnit
        let stream = drafting.draft(from: text, weightUnit: unit)
        streamTask = Task { [weak self] in
            await self?.runDraft(stream)
        }
    }

    /// Stops an in-flight turn. The first turn gives the unit back and returns to the
    /// description; an answer's turn returns to its question with the draft before it
    /// intact. Writes nothing either way, by construction: nothing is written anywhere
    /// until `createRoutine()`.
    func cancelDrafting() {
        streamTask?.cancel()
        streamTask = nil
        if conversation.isAsking, draft != nil {
            phase = .asking
            return
        }
        refundReservedUnit()
        clearDraft()
        phase = .describing
    }

    private func runDraft(_ stream: AsyncThrowingStream<RoutineDraftSnapshot, Error>) async {
        do {
            for try await snapshot in stream {
                if Task.isCancelled { return }
                apply(snapshot)
            }
            if Task.isCancelled { return }
            advance()
        } catch {
            // A cancelled stream is reported by `cancelDrafting()`, which has already
            // refunded and reset — it must not also land here as a failure the person
            // sees.
            if Task.isCancelled || error is CancellationError { return }
            refundReservedUnit()
            phase = .failed(Self.declinedMessage(for: error) ?? "ai_coach.routine_draft.error".localized)
        }
    }

    // MARK: - Asking for what is missing

    /// Sends the answer to the current question. **Consumes no allowance** — the unit
    /// belongs to the drafting session, which already holds it; charging per message would
    /// let one routine consume a free user's month.
    ///
    /// A name is applied here, in Swift, without a model turn: the answer *is* the name,
    /// and a turn could only get it wrong.
    func submitAnswer() {
        let text = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAsking, !text.isEmpty, let gap = conversation.pendingGap, draft != nil else { return }
        answerError = nil

        if gap == .name {
            draft?.name = text
            routineName = text
            answerText = ""
            advance()
            return
        }

        personWords.append(text)
        phase = .drafting
        let stream = drafting.answer(text, to: gap, weightUnit: weightUnit)
        streamTask = Task { [weak self] in
            await self?.runAnswer(stream)
        }
    }

    /// Stops answering and reviews what is there. Anything still unstated takes its Swift
    /// default, shown in the review as a value the person can change.
    func reviewNow() {
        guard canReviewNow else { return }
        conversation.stopAsking()
        phase = .review
        republish()
    }

    /// One answer's turn. Only the **finished** draft replaces the one on screen: the model
    /// writes the whole draft again, and streaming that into the list would empty it and
    /// refill it under the person's eyes.
    private func runAnswer(_ stream: AsyncThrowingStream<RoutineDraftSnapshot, Error>) async {
        var latest: RoutineDraftSnapshot?
        do {
            for try await snapshot in stream {
                if Task.isCancelled { return }
                latest = snapshot
            }
            if Task.isCancelled { return }
            guard let latest else {
                failAnswer()
                return
            }
            // An answer that yields no exercise never replaces the draft. Either the
            // person was asked which exercises and nothing usable came of the answer —
            // the model invented instead, and provenance dropped it all — or a re-draft
            // lost everything the draft already had. Both stay on the question, answerable
            // again, instead of falling through to an empty review.
            let next = groundedDraft(from: latest)
            guard !next.exercises.isEmpty else {
                failAnswer(message: draft?.exercises.isEmpty == false
                    ? nil
                    : "ai_coach.routine_draft.question.no_exercises".localized)
                return
            }
            answerText = ""
            draft = next
            republish()
            advance()
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            failAnswer(message: Self.declinedMessage(for: error))
        }
    }

    /// A follow-up that failed leaves the conversation where it was: same draft, same
    /// question, the answer still in the field. The session's unit is not refunded here —
    /// the session is still running; dismissing it refunds if nothing usable came of it.
    private func failAnswer(message: String? = nil) {
        streamTask = nil
        answerError = message ?? "ai_coach.routine_draft.question.error".localized
        phase = .asking
    }

    /// The message for words the model declined, or `nil` for any other failure. "Try
    /// again" would be wrong there: the same words are declined every time.
    private static func declinedMessage(for error: Error) -> String? {
        (error as? RoutineDraftingError) == .declinedByModel
            ? "ai_coach.routine_draft.error.declined".localized
            : nil
    }

    /// After a turn or an answer: ask about the next gap the draft still has, or hand off
    /// to the review — with no separate confirmation step.
    private func advance() {
        streamTask = nil
        guard let draft else { return }
        // Something a Create could write is on screen: the unit bought what it paid for,
        // whether or not the person answers another question.
        if !draft.hasNothingToCreate { isTicketRefundable = false }

        if conversation.askNext(of: draft.gaps) {
            phase = .asking
        } else {
            phase = .review
            // A draft the app may not write is a drafting session that gave the person
            // nothing — the generation succeeded, the outcome did not. The unit goes back
            // and the sheet says what was left out.
            if draft.hasNothingToCreate { refundReservedUnit() }
        }
        republish()
    }

    /// Grounds one snapshot and republishes the review list.
    ///
    /// Grounding runs per snapshot rather than once at the end so the list fills with the
    /// **library's** names as exercises complete, instead of with the model's spelling of
    /// them corrected afterwards.
    private func apply(_ snapshot: RoutineDraftSnapshot) {
        draft = groundedDraft(from: snapshot)
        republish()
    }

    private func groundedDraft(from snapshot: RoutineDraftSnapshot) -> GroundedRoutineDraft {
        var grounded = grounder.ground(
            snapshot,
            library: library,
            weightUnit: weightUnit,
            personWords: personWords.joined(separator: "\n")
        )
        // A name the conversation already has — drafted earlier or answered — survives a
        // turn that does not restate it. The model writes the whole draft each turn and
        // the name is the field it is most likely to leave out once nobody repeats it.
        if grounded.name.isEmpty, let previous = draft?.name { grounded.name = previous }
        return grounded
    }

    /// Rebuilds everything the sheet reads from `draft`. Called after a streamed snapshot
    /// and after the person resolves or removes a row, so both paths produce the list the
    /// same way.
    private func republish() {
        guard let draft else { return }
        // Only while streaming: once the draft is final the name is the person's to edit,
        // and an edit elsewhere in the list must not put the drafted one back.
        if phase == .drafting { routineName = draft.name }
        hasUnresolvedRows = draft.hasUnresolvedExercises
        hasCreatableExercises = !draft.hasNothingToCreate
        // Not while the draft is empty: then the only honest thing to say is the question
        // "which exercises?", not a list of things the model made up.
        droppedSummary = draft.droppedNames.isEmpty || draft.exercises.isEmpty
            ? nil
            : "ai_coach.routine_draft.dropped.body".localized(draft.droppedNames.joined(separator: ", "))
        // Until the review, an unstated set count reads as a question, not as the Swift
        // default: showing "3 sets" while asking how many would present a guess as data.
        rows = RoutineDraftRowComposer(weightUnit: weightUnit)
            .rows(for: draft, edits: edits, showsDefaults: phase == .review)
    }

    // MARK: - Resolving an unresolved row

    /// The library exercises to offer **before** the whole library for one unresolved
    /// row: the few the resolver found equally plausible, or empty when it found none.
    ///
    /// A bounded lookup over a list the generation schema caps at twelve — this is not a
    /// search.
    func candidates(for rowID: UUID) -> [Exercise] {
        draft?.exercises.first { $0.id == rowID }?.candidates ?? []
    }

    /// Points one unresolved row at a library exercise, keeping the set count, reps and
    /// weight the description gave it, and the place it had in the list.
    ///
    /// **It costs no allowance.** The unit was spent by the drafting session in full;
    /// correcting the machine's reading of a name is not a second use of the coach.
    func resolveRow(_ rowID: UUID, to exercise: Exercise) {
        guard phase == .review else { return }
        draft?.resolve(rowID, to: exercise)
        republish()
    }

    // MARK: - Editing the draft

    // Everything below is a Swift-side mutation of a draft the person already spent a
    // unit on: none of it touches the allowance gate or the drafting session, and none of
    // it writes — nothing is written anywhere until `createRoutine()`.

    /// Drops one row, resolved or not, along with any edit made to it.
    func removeRow(_ rowID: UUID) {
        guard phase == .review else { return }
        draft?.remove(rowID)
        edits[rowID] = nil
        republish()
    }

    /// Moves one row up (`-1`) or down (`+1`). The new position becomes the saved
    /// routine's `order` in `createRoutine()`.
    func moveRow(_ rowID: UUID, by offset: Int) {
        guard phase == .review else { return }
        draft?.move(rowID, by: offset)
        republish()
    }

    /// What `ConfigureExerciseSetsView` opens on for one resolved row: the person's last
    /// edit of it, or else its drafted scheme. `nil` for an unresolved row, which has no
    /// library exercise to configure yet.
    func configuration(for rowID: UUID) -> PendingRoutineExercise? {
        edits[rowID] ?? draft?.exercises.first { $0.id == rowID }?.pendingExercise(order: 0)
    }

    /// Takes back what `ConfigureExerciseSetsView` returned for one resolved row. The row
    /// keeps its place; `order` is assigned at Create from wherever it then stands.
    func updateConfiguration(
        _ rowID: UUID,
        sets: [ExerciseSet],
        alternatives: [PendingAlternative],
        targetRepMin: Int?,
        targetRepMax: Int?
    ) {
        guard phase == .review, var pending = configuration(for: rowID) else { return }
        pending.sets = sets
        pending.alternatives = alternatives
        pending.targetRepMin = targetRepMin
        pending.targetRepMax = targetRepMax
        edits[rowID] = pending
        republish()
    }

    // MARK: - Persisting

    /// Writes the draft through the one creation transaction this app has.
    ///
    /// `RoutinesViewModel.createRoutine(name:pendingExercises:)` materializes the routine,
    /// its exercises and their sets together, saves, and re-fetches — and that re-fetch is
    /// what syncs the new routine to the watch. There is no extra call to make here, and
    /// no second write path to maintain.
    func createRoutine() {
        guard phase == .review, let draft, !draft.hasNothingToCreate else { return }
        let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty
            ? "ai_coach.routine_draft.default_name".localized
            : trimmedName
        let pendingExercises = draft.pendingExercises(applying: edits)
        routines.createRoutine(name: name, pendingExercises: pendingExercises)
        // Composed here, once, from what was just written: the rows already carry any
        // edited summaries, and only resolved ones reached the store.
        createdRoutine = CreatedRoutineSummary(
            name: name,
            exerciseCount: pendingExercises.count,
            setCount: pendingExercises.reduce(0) { $0 + $1.sets.count },
            rows: rows.filter(\.isResolved)
        )
    }

    /// Throws the draft away — from the review, or mid-conversation. Nothing was ever
    /// written, so there is nothing to undo.
    func discard() {
        streamTask?.cancel()
        streamTask = nil
        refundReservedUnit()
        clearDraft()
        phase = .describing
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
        createdRoutine = nil
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
        edits = [:]
        conversation = RoutineDraftConversation()
        personWords = []
        droppedSummary = nil
        answerText = ""
        answerError = nil
        routineName = ""
        rows = []
        hasUnresolvedRows = false
        hasCreatableExercises = false
    }
}
