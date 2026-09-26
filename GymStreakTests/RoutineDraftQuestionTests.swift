//
//  RoutineDraftQuestionTests.swift
//  GymStreakTests
//
//  The AI routine draft (docs/ai-coach-routine-drafting.md), ticket 04: a description too
//  thin to draft from produces a question, not an invented routine.
//
//  What carries this ticket: what is missing is a Swift predicate over the grounded draft
//  (`GroundedRoutineDraft.gaps`), pinned here independent of any model; questions come
//  one at a time and each answer advances the draft; the whole conversation costs one
//  allowance unit; and stopping at any point either reviews what is there or writes
//  nothing.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftQuestionTests {

    private static let unstated = RoutineDraftGrounder.unstatedNumber

    // MARK: - The completeness predicate

    private func grounded(_ snapshot: RoutineDraftSnapshot) -> GroundedRoutineDraft {
        RoutineDraftGrounder().ground(
            snapshot,
            library: routineDraftLibrary(["Bench Press", "Squat"]),
            weightUnit: .kilograms
        )
    }

    @Test("A draft with no exercises lacks exercises, and nothing else is asked yet")
    func noExercisesIsTheOnlyGap() {
        let draft = grounded(routineDraftSnapshot(name: "", []))

        #expect(draft.gaps == [.exercises])
        #expect(!draft.isComplete)
    }

    @Test("Only exercises with no stated set count are named, before the name")
    func unstatedSetCountsComeBeforeTheName() {
        let draft = grounded(routineDraftSnapshot(name: "", [
            routineDraftEntry("Bench Press", sets: 4),
            routineDraftEntry("Squat", sets: Self.unstated),
            routineDraftEntry("Flurbelblatz", sets: Self.unstated),
        ]))

        #expect(draft.gaps == [.setCounts(exerciseNames: ["Squat", "Flurbelblatz"]), .name])
    }

    @Test("A named draft whose every exercise has a set count is complete")
    func completeDraftHasNoGaps() {
        let draft = grounded(routineDraftSnapshot(name: "Push Day", [
            routineDraftEntry("Bench Press", sets: 3, reps: Self.unstated, weight: 0),
        ]))

        // Unstated reps and load are not gaps: the ticket asks for name, exercises and
        // set counts, and the rest keeps its Swift default.
        #expect(draft.isComplete)
    }

    @Test("An unstated set count still carries the Swift default, marked as unstated")
    func unstatedSetCountKeepsItsDefault() throws {
        let draft = grounded(routineDraftSnapshot([routineDraftEntry("Bench Press", sets: Self.unstated)]))
        let exercise = try #require(draft.exercises.first)

        #expect(exercise.setCount == RoutineDraftGrounder.defaultSetCount)
        #expect(!exercise.isSetCountStated)
    }

    @Test("Resolving a row keeps whether its set count was stated")
    func resolvingKeepsTheStatedFlag() throws {
        let library = routineDraftLibrary(["Squat"])
        let draft = grounded(routineDraftSnapshot([routineDraftEntry("Flurbelblatz", sets: Self.unstated)]))
        let row = try #require(draft.exercises.first)

        #expect(!row.pointed(at: library[0]).isSetCountStated)
    }

    // MARK: - Names the person never said

    /// What the model actually wrote for "eine push routine" on device (2026-09-24): its
    /// own words for the workout, then categories until the schema's cap.
    private static let inventedOnDevice = ["Push", "Pull", "Squat", "Legs", "Chest", "Shoulders",
                                           "Back", "Arms", "Abs", "Core", "Legs", "Back"]

    @Test("The device replay: invented rows are dropped, and the draft asks for exercises")
    func deviceReplayAsksInsteadOfInventing() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot(name: "Eine Push Routine",
                                 Self.inventedOnDevice.map { routineDraftEntry($0, sets: Self.unstated) }),
            // "Pull" resolved to Face Pulls on device — the library here reproduces that.
            library: routineDraftLibrary(["Face Pulls", "Bench Press"]),
            weightUnit: .kilograms,
            personWords: "eine push routine"
        )

        #expect(draft.exercises.isEmpty)
        #expect(draft.gaps == [.exercises])
        // Reported once each; "Push" is the workout's name, not a dropped exercise.
        #expect(draft.droppedNames == ["Pull", "Squat", "Legs", "Chest", "Shoulders",
                                       "Back", "Arms", "Abs", "Core"])
    }

    @Test("A name the person wrote survives folding, plural and German spelling")
    func namesFromThePersonsWordsSurvive() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot(name: "Push-Tag", [
                routineDraftEntry("Bankdrücken"),
                routineDraftEntry("Squats"),
                routineDraftEntry("Bench Press"),
            ]),
            library: routineDraftLibrary(["Bankdrücken", "Squat", "Bench Press"]),
            weightUnit: .kilograms,
            personWords: "Push-Tag: bankdruecken 3x8, squat 5x5\nBENCH press"
        )

        #expect(draft.exercises.map(\.draftedName) == ["Bankdrücken", "Squats", "Bench Press"])
        #expect(draft.droppedNames.isEmpty)
    }

    @Test("A word hidden inside a longer word the person typed is not theirs")
    func wordInsideACompoundIsNotProvenance() {
        // Device, 2026-09-24: "Rücken" survived because fold("Bankdrücken") contains it.
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot(name: "Push", [routineDraftEntry("Rücken"), routineDraftEntry("Kniebeuge")]),
            library: routineDraftLibrary(["Kniebeugen"]),
            weightUnit: .kilograms,
            personWords: "eine push routine\nBankdrücken und Kniebeugen"
        )

        #expect(draft.droppedNames == ["Rücken"])
        #expect(draft.exercises.map(\.draftedName) == ["Kniebeuge"])
    }

    @Test("An exercise the library resolves is kept even when the routine is named after it")
    func resolvedExerciseInsideTheRoutineNameIsKept() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot(name: "Squat Day", [routineDraftEntry("Squat")]),
            library: routineDraftLibrary(["Squat"]),
            weightUnit: .kilograms,
            personWords: "squat day: squat five by five"
        )

        #expect(draft.exercises.count == 1)
    }

    @Test("An invented extra beside real exercises is dropped and said so")
    func inventedExtraIsReportedInTheSheet() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push Day", [
            routineDraftEntry("Bench Press"),
            routineDraftEntry("Row"),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press three by eight"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press"])
        #expect(harness.viewModel.droppedSummary == "ai_coach.routine_draft.dropped.body".localized("Row"))
        harness.viewModel.createRoutine()
        #expect(harness.routines.createdExercises.first?.map(\.exercise.name) == ["Bench Press"])
    }

    @Test("The device replay through the sheet: a question, and no list of made-up names")
    func deviceReplayThroughTheViewModel() async {
        let harness = RoutineDraftHarness.make(libraryNames: ["Face Pulls", "Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Eine Push Routine",
            Self.inventedOnDevice.map { routineDraftEntry($0, sets: Self.unstated) })]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "eine push routine"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.question == "ai_coach.routine_draft.question.exercises".localized)
        #expect(harness.viewModel.rows.isEmpty)
        #expect(harness.viewModel.droppedSummary == nil)
    }

    @Test("An answer's words count as the person's words")
    func answerWordsAreASource() async {
        let harness = await thinHarness()
        harness.drafting.answerSnapshots = [[routineDraftSnapshot(name: "Push", [routineDraftEntry("Bench Press")])]]

        await answer("bench press three by eight", in: harness)

        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press"])
        #expect(harness.viewModel.phase == .review)
    }

    @Test("Device round 6: an answer the model ignored stays on the question and says why")
    func answerThatYieldsNothingStaysOnTheQuestion() async {
        let harness = await thinHarness()
        // What came back on device for "Bankdrücken und Kniebeugen" (2026-09-24).
        harness.drafting.answerSnapshots = [[routineDraftSnapshot(name: "Eine Push Routine",
            ["Liegestütze", "Bizeps", "Trizeps", "Brust", "Schultern", "Beine", "Core", "Pull",
             "Rudern", "Abduktionen", "Rücken"].map { routineDraftEntry($0, sets: Self.unstated) })]]

        await answer("Bankdrücken und Kniebeugen", in: harness)

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.question == "ai_coach.routine_draft.question.exercises".localized)
        #expect(harness.viewModel.answerError == "ai_coach.routine_draft.question.no_exercises".localized)
        #expect(harness.viewModel.answerText == "Bankdrücken und Kniebeugen")
        #expect(harness.viewModel.rows.isEmpty)
    }

    // MARK: - The turn prompt

    @Test("Each turn sends the person's lines only: description first, then framed answers")
    func turnPromptIsThePersonsLines() {
        let prompt = RoutineDraftInstructions.prompt(from: [
            "eine push\nroutine",
            RoutineDraftInstructions.answer("Bankdrücken und Kniebeugen", to: .exercises),
        ])
        let lines = prompt.split(separator: "\n")

        // A description typed over two lines stays the first line.
        #expect(lines.count == 2)
        #expect(lines[0] == "eine push routine")
        #expect(lines[1].hasSuffix("Bankdrücken und Kniebeugen"))
    }

    // MARK: - Asking instead of inventing

    /// "a push routine" — a name and nothing else.
    private func thinHarness() async -> RoutineDraftHarness {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push", [])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "a push routine"
        harness.viewModel.submit()
        await harness.settle()
        return harness
    }

    private func answer(_ text: String, in harness: RoutineDraftHarness) async {
        harness.viewModel.answerText = text
        harness.viewModel.submitAnswer()
        await harness.settle()
    }

    @Test("A thin description produces a question, not a draft")
    func thinDescriptionAsks() async {
        let harness = await thinHarness()

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.question == "ai_coach.routine_draft.question.exercises".localized)
        #expect(harness.viewModel.rows.isEmpty)
        #expect(!harness.viewModel.canCreate)
        #expect(!harness.viewModel.canReviewNow)
        #expect(harness.routines.createCount == 0)
    }

    @Test("Each answer advances the draft, one question at a time, into the review")
    func answersAdvanceTheDraftIntoReview() async throws {
        let harness = await thinHarness()
        harness.drafting.answerSnapshots = [
            [routineDraftSnapshot(name: "Push", [
                routineDraftEntry("Bench Press", sets: Self.unstated, reps: 8, weight: 60),
                routineDraftEntry("Squat", sets: Self.unstated, reps: 5, weight: 100),
            ])],
            [routineDraftSnapshot(name: "Push", [
                routineDraftEntry("Bench Press", sets: 4, reps: 8, weight: 60),
                routineDraftEntry("Squat", sets: 4, reps: 5, weight: 100),
            ])],
        ]

        await answer("bench press and squats", in: harness)

        // The answer reached the model as an answer to *that* question…
        #expect(harness.drafting.answers.first?.gap == .exercises)
        #expect(harness.drafting.answers.first?.text == "bench press and squats")
        // …the draft grew, and the next question is the next gap.
        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press", "Squat"])
        #expect(harness.viewModel.question
            == "ai_coach.routine_draft.question.sets".localized("Bench Press, Squat"))
        // An unstated set count reads as the open question, never as the default.
        let summary = try #require(harness.viewModel.rows.first?.summary)
        #expect(summary.hasPrefix("ai_coach.routine_draft.sets_unstated".localized))
        #expect(harness.viewModel.answerText.isEmpty)

        await answer("four each", in: harness)

        // Complete: straight to the review, no separate confirmation step.
        #expect(harness.viewModel.phase == .review)
        #expect(harness.viewModel.question == nil)
        #expect(harness.viewModel.canCreate)
        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.sets.count) == [4, 4])
        #expect(harness.routines.createdNames == ["Push"])
    }

    @Test("The whole conversation consumes exactly one allowance unit")
    func wholeConversationCostsOneUnit() async {
        let harness = await thinHarness()
        let prewarmsBefore = harness.drafting.prewarmCount
        harness.drafting.answerSnapshots = [
            [routineDraftSnapshot(name: "", [routineDraftEntry("Bench Press", sets: Self.unstated)])],
            [routineDraftSnapshot(name: "", [routineDraftEntry("Bench Press", sets: 3)])],
        ]

        await answer("bench press", in: harness)
        #expect(harness.viewModel.phase == .asking)
        await answer("three", in: harness)

        #expect(harness.viewModel.phase == .review)
        // A description and two answers: three model turns, one unit.
        #expect(harness.drafting.turnCount == 3)
        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 0)
        #expect(harness.allowance.count(for: .coachChat) == 1)
        // No prewarm right before a respond call.
        #expect(harness.drafting.prewarmCount == prewarmsBefore)
    }

    @Test("A name is applied in Swift, without another model turn")
    func nameAnswerNeedsNoModelTurn() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot(name: "", [routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "bench press three by eight"
        harness.viewModel.submit()
        await harness.settle()
        #expect(harness.viewModel.question == "ai_coach.routine_draft.question.name".localized)

        await answer("  Upper A ", in: harness)

        #expect(harness.drafting.answers.isEmpty)
        #expect(harness.viewModel.phase == .review)
        #expect(harness.viewModel.routineName == "Upper A")
    }

    @Test("A name the draft already has survives a turn that does not restate it")
    func nameSurvivesAnAnswerTurn() async {
        let harness = await thinHarness()
        harness.drafting.answerSnapshots = [[routineDraftSnapshot(name: "", [routineDraftEntry("Bench Press")])]]

        await answer("bench press three by eight", in: harness)

        #expect(harness.viewModel.phase == .review)
        #expect(harness.viewModel.routineName == "Push")
    }

    @Test("A gap the answer did not fill is not asked twice; the review takes over")
    func unfilledGapIsNotAskedAgain() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press", sets: Self.unstated)])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "push day with bench press"
        harness.viewModel.submit()
        await harness.settle()

        await answer("not sure", in: harness)

        #expect(harness.viewModel.phase == .review)
        #expect(harness.drafting.answers.count == 1)
    }

    // MARK: - Stopping early

    @Test("Stopping early reviews what is there, with the default shown as a value")
    func reviewNowUsesTheSwiftDefault() async throws {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press", sets: Self.unstated)])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "push day with bench press"
        harness.viewModel.submit()
        await harness.settle()
        #expect(harness.viewModel.canReviewNow)

        harness.viewModel.reviewNow()

        #expect(harness.viewModel.phase == .review)
        let summary = try #require(harness.viewModel.rows.first?.summary)
        #expect(summary.hasPrefix("routine.sets_count".localized(RoutineDraftGrounder.defaultSetCount)))
        harness.viewModel.createRoutine()
        #expect(harness.routines.createdExercises.first?.first?.sets.count == RoutineDraftGrounder.defaultSetCount)
    }

    @Test("Create is refused while a question is open")
    func noCreateWhileAsking() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press", sets: Self.unstated)])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "bench press"
        harness.viewModel.submit()
        await harness.settle()

        harness.viewModel.createRoutine()

        #expect(harness.routines.createCount == 0)
    }

    @Test("Discarding mid-conversation writes nothing and refunds a session that gave nothing")
    func discardMidConversation() async {
        let harness = await thinHarness()

        harness.viewModel.discard()

        #expect(harness.viewModel.phase == .describing)
        #expect(harness.viewModel.question == nil)
        #expect(harness.routines.createCount == 0)
        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 1)
    }

    @Test("Dismissing the sheet mid-conversation writes nothing")
    func dismissMidConversation() async {
        let harness = await thinHarness()

        harness.viewModel.sheetWasDismissed()

        #expect(harness.routines.createCount == 0)
        #expect(harness.allowance.count(for: .coachChat) == 0)
    }

    // MARK: - A follow-up that goes wrong

    @Test("A failed answer keeps the draft, the question and the typed answer")
    func failedAnswerFallsBackToTheQuestion() async {
        let harness = await thinHarness()
        harness.drafting.failure = RoutineDraftTestFailure()

        await answer("bench press", in: harness)

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.question == "ai_coach.routine_draft.question.exercises".localized)
        #expect(harness.viewModel.answerError != nil)
        #expect(harness.viewModel.answerText == "bench press")
        #expect(harness.viewModel.routineName == "Push")
        // The session is still running; nothing is refunded until it ends.
        #expect(harness.allowance.refundCount == 0)
    }

    @Test("Words the model declines ask for different wording, and cost nothing")
    func declinedDescriptionAsksForDifferentWording() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.failure = RoutineDraftingError.declinedByModel
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push-Tag-Test: Bankdrücken 3 Sätze jeweils 8 Wiederholungen mit 80kg"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.phase == .failed("ai_coach.routine_draft.error.declined".localized))
        #expect(harness.viewModel.descriptionText.hasPrefix("Push-Tag-Test"))
        #expect(harness.allowance.count(for: .coachChat) == 0)
    }

    @Test("A declined answer stays on its question with the same advice")
    func declinedAnswerStaysOnTheQuestion() async {
        let harness = await thinHarness()
        harness.drafting.failure = RoutineDraftingError.declinedByModel

        await answer("bench press", in: harness)

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.answerError == "ai_coach.routine_draft.error.declined".localized)
    }

    @Test("An answer turn that loses every drafted exercise is a failed turn")
    func reDraftThatDropsEverythingIsRejected() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press", sets: Self.unstated)])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "bench press"
        harness.viewModel.submit()
        await harness.settle()
        harness.drafting.answerSnapshots = [[routineDraftSnapshot([])]]

        await answer("three", in: harness)

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press"])
        #expect(harness.viewModel.answerError != nil)
    }

    @Test("Stopping an answer's turn returns to its question with the draft intact")
    func cancellingAnAnswerReturnsToTheQuestion() async {
        let harness = await thinHarness()
        harness.viewModel.answerText = "bench press"
        harness.viewModel.submitAnswer()
        #expect(harness.viewModel.isDrafting)

        harness.viewModel.cancelDrafting()

        #expect(harness.viewModel.phase == .asking)
        #expect(harness.viewModel.routineName == "Push")
        #expect(harness.allowance.refundCount == 0)
    }
}
