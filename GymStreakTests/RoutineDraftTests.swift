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
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftTests {

    // MARK: - Fixtures

    /// Real `Exercise` models — `ExerciseNameResolver` matches on the stored `name`, so
    /// a stand-in would not exercise the folding it does.
    private func library(_ names: [String]) -> [Exercise] {
        let context = ModelContext(InMemoryModelContainer.make())
        return names.map { name in
            let exercise = Exercise(name: name)
            context.insert(exercise)
            return exercise
        }
    }

    private func entry(
        _ name: String,
        sets: Int = 3,
        reps: Int = 8,
        weight: Double = 60
    ) -> RoutineDraftEntry {
        RoutineDraftEntry(name: name, setCount: sets, reps: reps, weight: weight)
    }

    private func snapshot(name: String = "Push Day", _ entries: [RoutineDraftEntry]) -> RoutineDraftSnapshot {
        RoutineDraftSnapshot(name: name, exercises: entries)
    }

    // MARK: - The grounding pass

    @Test("A resolved name becomes the library exercise, under the library's own spelling")
    func resolvedNameBecomesTheLibraryExercise() {
        let lib = library(["Bankdrücken", "Kniebeugen"])

        let draft = RoutineDraftGrounder().ground(
            snapshot([entry("bankdruecken")]),
            library: lib,
            weightUnit: .kilograms
        )

        #expect(draft.exercises.count == 1)
        // The library's spelling, not the model's — the whole point of grounding.
        #expect(draft.exercises.first?.exercise.name == "Bankdrücken")
        #expect(draft.unmatchedNames.isEmpty)
    }

    @Test("An ambiguous name is left out and named, never resolved on the app's guess")
    func ambiguousNameIsLeftOut() {
        // "press" matches two distinct library names, so there is no exercise this draft
        // may claim. Ticket 02 makes it answerable; this ticket must not guess.
        let lib = library(["Bench Press", "Shoulder Press"])

        let draft = RoutineDraftGrounder().ground(
            snapshot([entry("press")]),
            library: lib,
            weightUnit: .kilograms
        )

        #expect(draft.exercises.isEmpty)
        #expect(draft.unmatchedNames == ["press"])
        #expect(draft.hasNothingToCreate)
    }

    @Test("An unmatched name is left out and named — never invented into the library")
    func unmatchedNameIsLeftOutAndReported() {
        let lib = library(["Bench Press"])

        let draft = RoutineDraftGrounder().ground(
            snapshot([entry("Bench Press"), entry("Flurbelblatz")]),
            library: lib,
            weightUnit: .kilograms
        )

        #expect(draft.exercises.count == 1)
        #expect(draft.exercises.first?.exercise.name == "Bench Press")
        #expect(draft.unmatchedNames == ["Flurbelblatz"])
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
            snapshot(name: "Push-Tag", [
                entry("Bankdrücken", sets: 3, reps: 8, weight: 60),
                entry("Schrägbankdrücken", sets: 3, reps: 10, weight: 22),
            ]),
            library: library(["Bankdrücken", "Kniebeugen"]),
            weightUnit: .kilograms
        )

        #expect(draft.exercises.map(\.exercise.name) == ["Bankdrücken"])
        #expect(draft.unmatchedNames == ["Schrägbankdrücken"])
        // The incline numbers went with the exercise that was left out — they did not
        // attach themselves to the flat bench press.
        #expect(draft.exercises.first?.reps == 8)
        #expect(draft.exercises.count == 1)
    }

    @Test("The same unmatched name twice is reported once")
    func unmatchedNamesAreDeduplicated() {
        let draft = RoutineDraftGrounder().ground(
            snapshot([entry("Flurbelblatz"), entry("flurbelblatz")]),
            library: library(["Bench Press"]),
            weightUnit: .kilograms
        )

        #expect(draft.unmatchedNames == ["Flurbelblatz"])
    }

    @Test("An unstated set or rep count gets the Swift-side default, never a model guess")
    func unstatedNumbersFallBackToSwiftDefaults() {
        let grounder = RoutineDraftGrounder()
        let draft = grounder.ground(
            snapshot([entry("Bench Press", sets: RoutineDraftGrounder.unstatedNumber,
                            reps: RoutineDraftGrounder.unstatedNumber, weight: 0)]),
            library: library(["Bench Press"]),
            weightUnit: .kilograms
        )

        let drafted = try? #require(draft.exercises.first)
        #expect(drafted?.setCount == RoutineDraftGrounder.defaultSetCount)
        #expect(drafted?.reps == RoutineDraftGrounder.defaultReps)
        // No weight stated is a drafted exercise without a load, not a missing one.
        #expect(drafted?.weightKilograms == 0)
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
            snapshot([entry("Bench Press", weight: 220)]),
            library: library(["Bench Press"]),
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
            snapshot([entry("Squat"), entry("Bench Press"), entry("Row")]),
            library: library(["Bench Press", "Row", "Squat"]),
            weightUnit: .kilograms
        )

        #expect(draft.exercises.map(\.exercise.name) == ["Squat", "Bench Press", "Row"])
    }

    // MARK: - Draft → the create-routine transaction

    @Test("The draft becomes pending exercises with sequential order and one set per set count")
    func draftMapsToPendingExercises() {
        let draft = RoutineDraftGrounder().ground(
            snapshot([
                entry("Bench Press", sets: 3, reps: 8, weight: 60),
                entry("Row", sets: 4, reps: 10, weight: 40),
            ]),
            library: library(["Bench Press", "Row"]),
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
            snapshot([entry("Bench Press"), entry("Flurbelblatz")]),
            library: library(["Bench Press"]),
            weightUnit: .kilograms
        )

        #expect(draft.pendingExercises().count == 1)
    }

    // MARK: - Preflight order

    @Test("An ineligible device never reaches a paywall — and never reaches the cap check")
    func unavailableDeviceIsNeverPaywalled() {
        let harness = makeHarness(availability: .deviceNotEligible)
        harness.routines.isRoutineCapReached = true

        #expect(harness.viewModel.requestDrafting() == false)
        // Unavailable is a disappointment, not a conversion opportunity (§4.3).
        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.allowance.consumeCount == 0)
    }

    @Test("A free user at the routine cap is stopped before typing, by routineCap")
    func routineCapStopsTheSheetFromOpening() {
        let harness = makeHarness()
        harness.routines.isRoutineCapReached = true

        #expect(harness.viewModel.requestDrafting() == false)
        #expect(harness.paywalls.presentedPlacements == [.routineCap])
        // The cap fires before the allowance: no unit is spent on a routine that could
        // not have been saved.
        #expect(harness.allowance.consumeCount == 0)
    }

    @Test("Below the cap on an eligible device, the sheet opens and nothing is metered yet")
    func preflightPassesWithoutMetering() {
        let harness = makeHarness()

        #expect(harness.viewModel.requestDrafting())
        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.allowance.consumeCount == 0)
    }

    // MARK: - The allowance unit

    @Test("One drafting session costs one unit, however many messages it takes")
    func oneUnitPerSessionNotPerMessage() async {
        let harness = makeHarness()
        harness.drafting.snapshots = [snapshot([entry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press three by eight"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.allowance.consumeCount == 1)

        // A second message inside the same session — what ticket 04 adds — reserves
        // nothing further.
        harness.viewModel.descriptionText = "make it four sets"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 0)
    }

    @Test("A failed generation gives the unit back")
    func failedGenerationRefunds() async {
        let harness = makeHarness()
        harness.drafting.failure = RoutineDraftTestFailure()
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 1)
        #expect(harness.allowance.count(for: .coachChat) == 0)
        #expect(harness.viewModel.phase == .failed("ai_coach.routine_draft.error".localized))
    }

    @Test("A draft in which nothing could be resolved gives the unit back")
    func emptyDraftRefunds() async {
        let harness = makeHarness()
        harness.drafting.snapshots = [snapshot([entry("Flurbelblatz")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Flurbelblatz day"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.viewModel.phase == .review)
        #expect(harness.viewModel.rows.isEmpty)
        // …and it says so, rather than pretending the description was empty.
        #expect(harness.viewModel.unmatchedNames == ["Flurbelblatz"])
        #expect(harness.allowance.refundCount == 1)
        #expect(harness.viewModel.canCreate == false)
    }

    @Test("Cancelling mid-stream refunds the unit and writes nothing")
    func cancellingRefundsAndWritesNothing() async {
        let harness = makeHarness()
        harness.drafting.snapshots = [snapshot([entry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day"
        harness.viewModel.submit()
        harness.viewModel.cancelDrafting()

        #expect(harness.allowance.consumeCount == 1)
        #expect(harness.allowance.refundCount == 1)
        #expect(harness.viewModel.phase == .describing)
        #expect(harness.routines.createCount == 0)
    }

    @Test("An exhausted allowance raises the coachChat paywall and keeps what was typed")
    func exhaustedAllowanceRaisesThePaywall() async {
        let harness = makeHarness()
        for _ in 0..<ProFeatureCaps.freeCoachChatMessagesPerMonth {
            _ = harness.gate.requestGeneration()
        }
        harness.paywalls.reset()
        harness.allowance.resetCallCounts()
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.paywalls.presentedPlacements == [.coachChat])
        #expect(harness.allowance.consumeCount == 0)
        // Nobody loses what they wrote to a gate.
        #expect(harness.viewModel.descriptionText == "Push day")
        #expect(harness.viewModel.phase == .describing)
    }

    // MARK: - Creating

    @Test("Create writes once, through the shared transaction, with the drafted name")
    func createGoesThroughTheSharedTransaction() async {
        let harness = makeHarness()
        harness.drafting.snapshots = [
            snapshot(name: "Push Day", [entry("Bench Press", sets: 3, reps: 8, weight: 60)])
        ]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day: bench press three by eight at sixty"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.viewModel.canCreate)
        harness.viewModel.createRoutine()

        #expect(harness.routines.createdNames == ["Push Day"])
        #expect(harness.routines.createdExercises.first?.count == 1)
        #expect(harness.routines.createdExercises.first?.first?.exercise.name == "Bench Press")
        #expect(harness.viewModel.didCreateRoutine)
    }

    @Test("A draft with no name of its own is created under the fallback name")
    func namelessDraftGetsTheFallbackName() async {
        let harness = makeHarness()
        harness.drafting.snapshots = [snapshot(name: "   ", [entry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "bench press"
        harness.viewModel.submit()
        await settle(harness.viewModel)
        harness.viewModel.createRoutine()

        #expect(harness.routines.createdNames == ["ai_coach.routine_draft.default_name".localized])
    }

    @Test("Discarding, and dismissing the sheet, write nothing")
    func discardWritesNothing() async {
        let harness = makeHarness()
        harness.drafting.snapshots = [snapshot([entry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)

        harness.viewModel.descriptionText = "Push day"
        harness.viewModel.submit()
        await settle(harness.viewModel)

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
        let harness = makeHarness()
        harness.drafting.snapshots = [snapshot([entry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .pounds)

        harness.viewModel.descriptionText = "Push day"
        harness.viewModel.submit()
        await settle(harness.viewModel)

        #expect(harness.drafting.requestedUnits == [.pounds])
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: RoutineDraftViewModel
        let gate: AICoachAllowanceGate
        let drafting: FakeRoutineDrafting
        let routines: FakeRoutineCreating
        let paywalls: RecordingPaywallPresenter
        let allowance: SpyAllowanceStore
        let exercises: FakeExerciseRepository
    }

    private func makeHarness(
        state: ProEntitlementState = .free,
        availability: AICoachAvailabilityState = .available,
        libraryNames: [String] = ["Bench Press", "Row", "Squat", "Bankdrücken"]
    ) -> Harness {
        let paywalls = RecordingPaywallPresenter()
        let allowance = SpyAllowanceStore()
        let availabilityStub = StubAICoachAvailability(state: availability)
        let gate = AICoachAllowanceGate(
            surface: .coachChat,
            entitlements: StubProEntitlements(state: state),
            paywalls: paywalls,
            allowance: allowance,
            availability: availabilityStub,
            isGatingEnabled: true
        )
        let drafting = FakeRoutineDrafting()
        let routines = FakeRoutineCreating()
        let exercises = FakeExerciseRepository(exercises: library(libraryNames))
        return Harness(
            viewModel: RoutineDraftViewModel(
                allowanceGate: gate,
                drafting: drafting,
                exerciseRepository: exercises,
                routines: routines,
                paywalls: paywalls,
                availability: availabilityStub
            ),
            gate: gate,
            drafting: drafting,
            routines: routines,
            paywalls: paywalls,
            allowance: allowance,
            exercises: exercises
        )
    }

    /// Lets the scripted stream drain. The fake yields into an unbounded buffer and
    /// finishes synchronously, so this settles in a handful of turns; the bound only
    /// stops a bug from hanging the suite.
    private func settle(_ viewModel: RoutineDraftViewModel, turns: Int = 500) async {
        for _ in 0..<turns {
            if !viewModel.isDrafting { return }
            await Task.yield()
        }
        Issue.record("the draft never finished")
    }
}
