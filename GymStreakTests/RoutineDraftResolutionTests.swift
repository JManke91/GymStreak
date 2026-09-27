//
//  RoutineDraftResolutionTests.swift
//  GymStreakTests
//
//  The AI routine draft (docs/ai-coach-routine-drafting.md), ticket 02: an exercise name
//  the live library could not place becomes a row the person can answer.
//
//  Three things carry this ticket. The two failing cases stay apart — an ambiguous name
//  can offer the few library exercises it matched, and an unmatched one has only the whole
//  library to offer. Answering a row keeps the figures the description gave it, in the
//  place it had. And an unresolved row can never reach the store: it is excluded from what
//  Create writes whether the person answers it, removes it, or leaves it alone.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftResolutionTests {

    // MARK: - Ambiguous: the candidates are offered

    @Test("An ambiguous name keeps the library exercises it matched, to offer first")
    func ambiguousNameCarriesItsCandidates() throws {
        // "press" matches two distinct library names equally well.
        let lib = routineDraftLibrary(["Bench Press", "Shoulder Press", "Squat"])

        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("press")]),
            library: lib,
            weightUnit: .kilograms
        )

        let drafted = try #require(draft.exercises.first)
        #expect(drafted.isResolved == false)
        // The short, correct list — not the whole library, and not nothing.
        #expect(Set(drafted.candidates.map(\.name)) == ["Bench Press", "Shoulder Press"])
        // What the person said survives, because it is the only thing they recognise the
        // row by.
        #expect(drafted.draftedName == "press")
    }

    @Test("A name nothing matched offers no candidates — the answer is the whole library")
    func unmatchedNameOffersNoCandidates() throws {
        let draft = RoutineDraftGrounder().ground(
            routineDraftSnapshot([routineDraftEntry("Flurbelblatz")]),
            library: routineDraftLibrary(["Bench Press", "Squat"]),
            weightUnit: .kilograms
        )

        let drafted = try #require(draft.exercises.first)
        #expect(drafted.isResolved == false)
        #expect(drafted.candidates.isEmpty)
    }

    @Test("The sheet gets the candidates for the row the person tapped")
    func viewModelHandsTheCandidatesToThePicker() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press", "Shoulder Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "press day"
        harness.viewModel.submit()
        await harness.settle()

        let row = try #require(harness.viewModel.rows.first)
        #expect(row.isResolved == false)
        #expect(Set(harness.viewModel.candidates(for: row.id).map(\.name))
            == ["Bench Press", "Shoulder Press"])
    }

    // MARK: - The unresolved row itself

    @Test("An unresolved row shows what the person said, never a blank or a placeholder")
    func unresolvedRowShowsTheDraftedName() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([
            routineDraftEntry("Bench Press"),
            routineDraftEntry("Schrägbank Kurzhantel", sets: 4, reps: 12, weight: 22),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press 3x8 at 60 kg, Schrägbank Kurzhantel 4x12 mit 22 kg"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press", "Schrägbank Kurzhantel"])
        let unresolved = try #require(harness.viewModel.rows.last)
        #expect(unresolved.isResolved == false)
        // Its figures are on screen too — they are what resolving the row keeps.
        #expect(unresolved.summary.contains("4"))
        #expect(unresolved.summary.contains("12"))
        #expect(harness.viewModel.hasUnresolvedRows)
    }

    // MARK: - Resolving

    @Test("Choosing an exercise resolves the row in place, keeping its sets, reps and weight")
    func resolvingKeepsTheFiguresAndThePosition() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press", "Incline Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([
            routineDraftEntry("Schrägbank Kurzhantel", sets: 4, reps: 12, weight: 22),
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: Schrägbank Kurzhantel 4x12 mit 22 kg, bench press 3x8 at 60 kg"
        harness.viewModel.submit()
        await harness.settle()

        let unresolved = try #require(harness.viewModel.rows.first)
        let incline = try #require(harness.exercises.exercises.first { $0.name == "Incline Press" })
        harness.viewModel.resolveRow(unresolved.id, to: incline)

        // In place: the described order is still the routine's order.
        #expect(harness.viewModel.rows.map(\.name) == ["Incline Press", "Bench Press"])
        #expect(harness.viewModel.rows.allSatisfy { $0.isResolved })
        #expect(harness.viewModel.hasUnresolvedRows == false)

        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.exercise.name) == ["Incline Press", "Bench Press"])
        // The figures the description gave it, not the defaults.
        #expect(written[0].sets.count == 4)
        #expect(written[0].sets.allSatisfy { $0.reps == 12 && $0.weight == 22 })
    }

    @Test("Resolving an already-resolved row changes nothing — swapping one is ticket 03")
    func resolvingAResolvedRowIsANoOp() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press", "Squat"])
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Bench Press")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press"
        harness.viewModel.submit()
        await harness.settle()

        let row = try #require(harness.viewModel.rows.first)
        let squat = try #require(harness.exercises.exercises.first { $0.name == "Squat" })
        harness.viewModel.resolveRow(row.id, to: squat)

        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press"])
    }

    // MARK: - Removing

    @Test("An unresolved row can be removed outright")
    func unresolvedRowCanBeRemoved() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([
            routineDraftEntry("Bench Press"),
            routineDraftEntry("Flurbelblatz"),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press 3x8 at 60 kg, Flurbelblatz 4x12 at 22 kg"
        harness.viewModel.submit()
        await harness.settle()

        let unresolved = try #require(harness.viewModel.rows.last)
        harness.viewModel.removeRow(unresolved.id)

        #expect(harness.viewModel.rows.map(\.name) == ["Bench Press"])
        #expect(harness.viewModel.hasUnresolvedRows == false)
        // Removing is not writing — nothing is written until Create.
        #expect(harness.routines.createCount == 0)
    }

    // MARK: - Create can never write an unresolved row

    @Test("An unresolved row is excluded from Create, and the sheet says so beforehand")
    func createExcludesUnresolvedRows() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60),
            routineDraftEntry("Flurbelblatz", sets: 4, reps: 12, weight: 22),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: bench press 3x8 at 60 kg, Flurbelblatz 4x12 at 22 kg"
        harness.viewModel.submit()
        await harness.settle()

        // Before tapping Create, the sheet can already say which rows are left out.
        #expect(harness.viewModel.hasUnresolvedRows)
        #expect(harness.viewModel.canCreate)

        harness.viewModel.createRoutine()

        let written = try #require(harness.routines.createdExercises.first)
        #expect(written.map(\.exercise.name) == ["Bench Press"])
        #expect(written.map(\.order) == [0])
    }

    @Test("A draft of nothing but unresolved rows offers no Create at all")
    func nothingResolvedMeansNoCreate() async {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot([routineDraftEntry("Flurbelblatz")])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Flurbelblatz day"
        harness.viewModel.submit()
        await harness.settle()

        #expect(harness.viewModel.canCreate == false)
        harness.viewModel.createRoutine()
        #expect(harness.routines.createCount == 0)
    }

    // MARK: - Allowance

    @Test("Resolving and removing rows cost no additional allowance unit")
    func resolvingCostsNoAllowance() async throws {
        let harness = RoutineDraftHarness.make(
            libraryNames: ["Bench Press", "Shoulder Press", "Squat"]
        )
        harness.drafting.snapshots = [routineDraftSnapshot([
            routineDraftEntry("press"),
            routineDraftEntry("Flurbelblatz"),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push day: press, Flurbelblatz"
        harness.viewModel.submit()
        await harness.settle()

        let spentByTheDraft = harness.allowance.consumeCount

        let first = try #require(harness.viewModel.rows.first)
        let squat = try #require(harness.exercises.exercises.first { $0.name == "Squat" })
        harness.viewModel.resolveRow(first.id, to: squat)
        let second = try #require(harness.viewModel.rows.last)
        harness.viewModel.removeRow(second.id)
        harness.viewModel.createRoutine()

        // The unit was spent by the drafting session. Correcting the machine's reading of
        // a name is not a second use of the coach.
        #expect(harness.allowance.consumeCount == spentByTheDraft)
    }
}
