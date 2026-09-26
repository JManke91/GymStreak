//
//  RoutineDraftTests.swift
//  GymStreakTests
//
//  The AI routine draft (docs/ai-coach-routine-drafting.md), ticket 01.
//
//  Four things carry this ticket and each has its section below: an exercise name the
//  live library cannot place is never invented and never silently dropped; the draft
//  becomes exactly the `[PendingRoutineExercise]` the existing create-routine
//  transaction takes; the preflight runs availability → routine cap → allowance, in that
//  order; and one drafting session costs one allowance unit, refunded when it gave the
//  person nothing.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftTests {

    // MARK: - The grounding pass

    @Test("A resolved name becomes the library exercise, under the library's own spelling")
    func resolvedNameBecomesTheLibraryExercise() {
        let lib = routineDraftLibrary(["Bankdrücken", "Kniebeugen"])

        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("bankdruecken")]),
            library: lib,
            weightUnit: .kilograms
        )

        #expect(draft.exercises.count == 1)
        // The library's spelling, not the model's — the whole point of grounding.
        #expect(draft.exercises.first?.exercise?.name == "Bankdrücken")
        #expect(draft.exercises.allSatisfy { $0.isResolved })
    }

    @Test("An ambiguous name is left out and named, never resolved on the app's guess")
    func ambiguousNameIsLeftOut() {
        // "press" matches two distinct library names, so there is no exercise this draft
        // may claim. Ticket 02 makes it answerable (see RoutineDraftResolutionTests);
        // nothing may guess at it in the meantime.
        let lib = routineDraftLibrary(["Bench Press", "Shoulder Press"])

        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("press")]),
            library: lib,
            weightUnit: .kilograms
        )

        #expect(draft.resolvedExercises.isEmpty)
        #expect(draft.exercises.map(\.draftedName) == ["press"])
        #expect(draft.hasNothingToCreate)
    }

    @Test("An unmatched name is left out and named — never invented into the library")
    func unmatchedNameIsLeftOutAndReported() {
        let lib = routineDraftLibrary(["Bench Press"])

        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("Bench Press"), routineDraftEntry("Flurbelblatz")]),
            library: lib,
            weightUnit: .kilograms
        )

        #expect(draft.resolvedExercises.count == 1)
        #expect(draft.resolvedExercises.first?.exercise?.name == "Bench Press")
        #expect(draft.exercises.filter { !$0.isResolved }.map(\.draftedName) == ["Flurbelblatz"])
    }

    /// The device failure this feature shipped with on 2026-09-16, pinned at the level a
    /// person actually sees it: "Push-Tag: Bankdrücken 3 Sätze à 8 mit 60 kg,
    /// Schrägbankdrücken 3 Mal 10 mit 22 kg" against a library holding only the stem
    /// produced **two rows both reading "Bankdrücken"**, the second carrying the incline
    /// numbers. The routine was one tap from being written that way.
    ///
    /// Root cause and the general fix live in `ExerciseNameResolver`
    /// (`compoundPrefixDoesNotResolveToTheStemExercise`); this asserts the consequence
    /// here — the exercise is left out and named, never quietly swapped for another.
    @Test("A German compound is left out, never swapped for the stem exercise")
    func germanCompoundIsNotSwappedForTheStem() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot(name: "Push-Tag", [
                routineDraftEntry("Bankdrücken", sets: 3, reps: 8, weight: 60),
                routineDraftEntry("Schrägbankdrücken", sets: 3, reps: 10, weight: 22),
            ]),
            library: routineDraftLibrary(["Bankdrücken", "Kniebeugen"]),
            weightUnit: .kilograms
        )

        #expect(draft.resolvedExercises.compactMap { $0.exercise?.name } == ["Bankdrücken"])
        #expect(draft.exercises.filter { !$0.isResolved }.map(\.draftedName) == ["Schrägbankdrücken"])
        // The incline numbers went with the exercise that was left out — they did not
        // attach themselves to the flat bench press.
        #expect(draft.resolvedExercises.first?.reps == 8)
        #expect(draft.resolvedExercises.count == 1)
    }

    @Test("The same unmatched name twice stays two rows, each answerable on its own")
    func theSameUnmatchedNameTwiceStaysTwoRows() {
        // Two descriptions of the same unknown movement are two pieces of work with their
        // own figures, so each keeps its own row rather than being collapsed into one.
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([
                routineDraftEntry("Flurbelblatz", sets: 3, reps: 8),
                routineDraftEntry("flurbelblatz", sets: 5, reps: 12),
            ]),
            library: routineDraftLibrary(["Bench Press"]),
            weightUnit: .kilograms
        )

        #expect(draft.exercises.map(\.draftedName) == ["Flurbelblatz", "flurbelblatz"])
        #expect(draft.exercises.map(\.setCount) == [3, 5])
        #expect(Set(draft.exercises.map(\.id)).count == 2)
    }

    @Test("An unstated set or rep count gets the Swift-side default, never a model guess")
    func unstatedNumbersFallBackToSwiftDefaults() throws {
        let grounder = RoutineDraftGrounder()
        let draft = grounder.ground(
            routineDraftSnapshot([routineDraftEntry("Bench Press", sets: RoutineDraftGrounder.unstatedNumber,
                            reps: RoutineDraftGrounder.unstatedNumber, weight: 0)]),
            library: routineDraftLibrary(["Bench Press"]),
            weightUnit: .kilograms
        )

        let drafted = try #require(draft.exercises.first)
        #expect(drafted.setCount == RoutineDraftGrounder.defaultSetCount)
        #expect(drafted.reps == RoutineDraftGrounder.defaultReps)
        // No weight stated is a drafted exercise without a load, not a missing one.
        #expect(drafted.weightKilograms == 0)
    }

    @Test("Absurd figures are bounded before they can reach the store")
    func figuresAreBounded() {
        let grounder = RoutineDraftGrounder()
        #expect(grounder.boundedSetCount(9_999) == RoutineDraftGrounder.maximumSetCount)
        #expect(grounder.boundedReps(9_999) == RoutineDraftGrounder.maximumReps)
        #expect(grounder.boundedSetCount(-4) == RoutineDraftGrounder.defaultSetCount)
        #expect(grounder.kilograms(-20, in: .kilograms) == 0)
        #expect(grounder.kilograms(5_000, in: .kilograms) == WeightUnit.maximumKilograms)
    }

    @Test("A weight drafted in pounds is stored as canonical kilograms")
    func poundsAreConvertedOnce() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("Bench Press", weight: 220)]),
            library: routineDraftLibrary(["Bench Press"]),
            weightUnit: .pounds
        )

        let kilograms = draft.exercises.first?.weightKilograms ?? 0
        #expect(abs(kilograms - WeightUnit.pounds.kilograms(fromDisplay: 220)) < 0.0001)
        // Sanity: it is genuinely kilograms now, not the pounds figure passed through.
        #expect(kilograms < 220)
    }

    @Test("Drafted exercises keep the order the description gave them")
    func orderIsPreserved() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("Squat"), routineDraftEntry("Bench Press"), routineDraftEntry("Row")]),
            library: routineDraftLibrary(["Bench Press", "Row", "Squat"]),
            weightUnit: .kilograms
        )

        #expect(draft.exercises.compactMap { $0.exercise?.name } == ["Squat", "Bench Press", "Row"])
    }

    // MARK: - Draft → the create-routine transaction

    @Test("The draft becomes pending exercises with sequential order and one set per set count")
    func draftMapsToPendingExercises() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([
                routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
                routineDraftEntry("Row", sets: 4, reps: 10, weight: 40),
            ]),
            library: routineDraftLibrary(["Bench Press", "Row"]),
            weightUnit: .kilograms
        )

        let pending = draft.pendingExercises()

        #expect(pending.count == 2)
        // `order` comes from the draft's own position, which is what makes the routine
        // read in the order the person described it.
        #expect(pending.map(\.order) == [0, 1])
        #expect(pending[0].exercise.name == "Bench Press")
        #expect(pending[0].sets.count == 3)
        #expect(pending[0].sets.map(\.order) == [0, 1, 2])
        #expect(pending[0].sets.allSatisfy { $0.reps == 8 && $0.weight == 60 })
        #expect(pending[1].sets.count == 4)
        #expect(pending[1].sets.allSatisfy { $0.reps == 10 && $0.weight == 40 })
        // Nothing in a typed description expresses these, so nothing is invented.
        #expect(pending.allSatisfy { $0.alternatives.isEmpty })
        #expect(pending.allSatisfy { $0.targetRepMin == nil && $0.targetRepMax == nil })
    }

    @Test("An unmatched exercise never reaches the transaction")
    func unmatchedExercisesAreNotPersisted() {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("Bench Press"), routineDraftEntry("Flurbelblatz")]),
            library: routineDraftLibrary(["Bench Press"]),
            weightUnit: .kilograms
        )

        #expect(draft.pendingExercises().count == 1)
    }

    // MARK: - Preflight order

    @Test("An ineligible device never reaches a paywall — and never reaches the cap check")
    func unavailableDeviceIsNeverPaywalled() {
        let harness = RoutineDraftHarness.make(availability: .deviceNotEligible)
        harness.routines.isRoutineCapReached = true

        #expect(harness.viewModel.requestDrafting() == false)
        // Unavailable is a disappointment, not a conversion opportunity (§4.3).
        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.allowance.consumeCount == 0)
    }

    @Test("A free user at the routine cap is stopped before typing, by routineCap")
    func routineCapStopsTheSheetFromOpening() {
        let harness = RoutineDraftHarness.make()
        harness.routines.isRoutineCapReached = true

        #expect(harness.viewModel.requestDrafting() == false)
        #expect(harness.paywalls.presentedPlacements == [.routineCap])
        // The cap fires before the allowance: no unit is spent on a routine that could
        // not have been saved.
        #expect(harness.allowance.consumeCount == 0)
    }

    @Test("Below the cap on an eligible device, the sheet opens and nothing is metered yet")
    func preflightPassesWithoutMetering() {
        let harness = RoutineDraftHarness.make()

        #expect(harness.viewModel.requestDrafting())
        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.allowance.consumeCount == 0)
    }

    // MARK: - The allowance unit

    @Test("One drafting session costs one unit, however many messages it takes")
    func oneUnitPerSessionNotPerMessage() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press three by eight"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.allowance.consumeCount == 1)

        // A second message inside the same session — what ticket 04 adds — reserves
        // nothing further.
        harness.viewModel.descriptionText = "bench press four sets"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 0)
    }

    @Test("A failed generation gives the unit back")
    func failedGenerationRefunds() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.failure = RoutineDraftTestFailure()
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 1)
        #expect(harness.allowance.count(for: .coachChat) == 0)
        #expect(harness.viewModel.phase == .failed("ai_coach.routine_draft.error".localized))
    }

    @Test("A draft in which nothing could be resolved gives the unit back")
    func emptyDraftRefunds() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Flurbelblatz")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Flurbelblatz day"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.phase == .review)
        // The row is on screen — unresolved, so Create would write nothing — rather than
        // the description being pretended empty.
        #expect(harness.viewModel.rows.map(\.name) == ["Flurbelblatz"])
        #expect(harness.viewModel.rows.allSatisfy { !$0.isResolved })
        #expect(harness.viewModel.hasUnresolvedRows)
        #expect(harness.viewModel.hasCreatableExercises == false)
        #expect(harness.allowance.refundCount == 1)
        #expect(harness.viewModel.canCreate == false)
    }

    @Test("Cancelling mid-stream refunds the unit and writes nothing")
    func cancellingRefundsAndWritesNothing() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press"
        harness.viewModel.submit()
        harness.viewModel.cancelDrafting()

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 1)
        #expect(harness.viewModel.phase == .describing)
        #expect(harness.routines.createCount == 0)
    }

    @Test("An exhausted allowance raises the coachChat paywall and keeps what was typed")
    func exhaustedAllowanceRaisesThePaywall() async {
        let harness = RoutineDraftHarness.make()
        for _ in 0..<ProFeatureCaps.freeCoachChatMessagesPerMonth {
            _ = harness.gate.requestGeneration()
        }
        harness.paywalls.reset()
        harness.allowance.resetCallCounts()
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.paywalls.presentedPlacements == [.coachChat])
        #expect(harness.allowance.consumeCount == 0)
        // Nobody loses what they wrote to a gate.
        #expect(harness.viewModel.descriptionText == "Push day")
        #expect(harness.viewModel.phase == .describing)
    }

    // MARK: - Creating

    @Test("Create writes once, through the shared transaction, with the drafted name")
    func createGoesThroughTheSharedTransaction() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [
            routineDraftSnapshot(name: "Push Day", [routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60)])
        ]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press three by eight at sixty"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.canCreate)
        harness.viewModel.createRoutine()

        #expect(harness.routines.createdNames == ["Push Day"])
        #expect(harness.routines.createdExercises.first?.count == 1)
        #expect(harness.routines.createdExercises.first?.first?.exercise.name == "Bench Press")
        #expect(harness.viewModel.didCreateRoutine)
    }

    @Test("Create hands the confirmation what was written: name, totals, numbered exercises")
    func createProducesTheConfirmationSummary() async throws {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push Day", [
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
            routineDraftEntry("Flurbelblatz"),
            routineDraftEntry("Squat", sets: 4, reps: 5, weight: 100),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press, Flurbelblatz, squat"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.createdRoutine == nil)
        harness.viewModel.createRoutine()

        let created = try #require(harness.viewModel.createdRoutine)
        #expect(created.name == "Push Day")
        // The unresolved row was left out of the write, so it is left out here too, and
        // the numbering closes the gap exactly as `order` does.
        #expect(created.exercises.map(\.name) == ["Bench Press", "Squat"])
        #expect(created.exercises.map(\.number) == [1, 2])
        #expect(created.exercises.map(\.isLast) == [false, true])
        #expect(created.totals == [
            "ai_coach.routine_draft.created.exercises.other".localized(2),
            "routine.sets_count".localized(7),
        ].joined(separator: " • "))

        // The next drafting session starts without it.
        harness.viewModel.sheetWasDismissed()
        #expect(harness.viewModel.createdRoutine == nil)
    }

    @Test("A one-exercise, one-set routine reads in the singular")
    func confirmationTotalsUseTheSingular() {
        let summary = CreatedRoutineSummary(name: "Solo", exerciseCount: 1, setCount: 1, rows: [])
        #expect(summary.totals == [
            "ai_coach.routine_draft.created.exercises.one".localized,
            "ai_coach.routine_draft.created.sets.one".localized,
        ].joined(separator: " • "))
    }

    @Test("A draft reviewed without a name of its own is created under the fallback name")
    func namelessDraftGetsTheFallbackName() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot(name: "   ", [routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "bench press"
        harness.viewModel.submit()
        await harness.settle()
        // Since ticket 04 a nameless draft asks for a name; skipping the question is what
        // leaves the fallback to Create.
        #expect(harness.viewModel.question == "ai_coach.routine_draft.question.name".localized)
        harness.viewModel.reviewNow()
        harness.viewModel.createRoutine()

        #expect(harness.routines.createdNames == ["ai_coach.routine_draft.default_name".localized])
    }

    @Test("Discarding, and dismissing the sheet, write nothing")
    func discardWritesNothing() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press"
        harness.viewModel.submit()
        await harness.settle()

        harness.viewModel.discard()
        #expect(harness.routines.createCount == 0)
        #expect(harness.viewModel.rows.isEmpty)

        harness.viewModel.sheetWasDismissed()
        #expect(harness.routines.createCount == 0)
        #expect(harness.viewModel.descriptionText.isEmpty)
        #expect(harness.viewModel.phase == .describing)
    }

    @Test("The reader's unit reaches the drafting session")
    func readersUnitReachesTheSession() async {
        let harness = RoutineDraftHarness.make()
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .pounds)

        harness.viewModel.descriptionText = "Push day: bench press"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.drafting.requestedUnits == [.pounds])
    }
}
