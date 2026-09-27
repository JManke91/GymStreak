//
//  RoutineDraftGoalsTests.swift
//  GymStreakTests
//
//  The AI routine draft (docs/ai-coach-routine-drafting.md), ticket 05: a rep-range goal
//  and a rest time per drafted exercise.
//
//  What carries this ticket: a goal exists only when the description stated one — its
//  absence is the ordinary case and reaches the store as nil, never as a guess and never
//  as the text "nil" — and rest defaults to 60 s in Swift. Every case is asserted after a
//  real round trip through `createRoutine` into SwiftData.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct RoutineDraftGoalsTests {

    // MARK: - Round trip

    /// Drafts `entry` against a one-exercise library, creates it through a real
    /// `RoutinesViewModel` over an in-memory store, and returns the persisted exercise
    /// with the review row the sheet showed for it.
    private func persist(
        _ entry: RoutineDraftEntry,
        description: String = "Push: bench press 3 sets of 8 at 60 kg"
    ) async throws -> (RoutineExercise, RoutineDraftRow) {
        let context = ModelContext(InMemoryModelContainer.make())
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        let routines = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: StubProEntitlements(state: .free),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )
        let availability = StubAICoachAvailability(state: .available)
        let paywalls = RecordingPaywallPresenter()
        let drafting = FakeRoutineDrafting()
        drafting.snapshots = [routineDraftSnapshot(name: "Push", [entry])]
        let viewModel = RoutineDraftViewModel(
            allowanceGate: AICoachAllowanceGate(
                surface: .coachChat,
                entitlements: StubProEntitlements(state: .free),
                paywalls: paywalls,
                allowance: SpyAllowanceStore(),
                availability: availability,
                isGatingEnabled: true
            ),
            drafting: drafting,
            exerciseRepository: FakeExerciseRepository(exercises: [bench]),
            routines: routines,
            paywalls: paywalls,
            availability: availability
        )
        viewModel.onAppear(weightUnit: .kilograms)
        viewModel.descriptionText = description
        viewModel.submit()
        for _ in 0..<500 where viewModel.isDrafting { await Task.yield() }

        let row = try #require(viewModel.rows.first)
        viewModel.createRoutine()
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        let exercise = try #require(routine.routineExercisesList.first)
        return (exercise, row)
    }

    // MARK: - Rep goal

    @Test("A stated rep range is persisted as the exercise's goal, and the sets start at its low end")
    func statedRangePersists() async throws {
        let (exercise, row) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 0, weight: 60, repRange: (8, 12)),
            description: "Push: bench press 3 sets of 8 to 12 at 60 kg"
        )

        #expect(exercise.targetRepMin == 8)
        #expect(exercise.targetRepMax == 12)
        #expect(exercise.hasRepRangeGoal)
        #expect(exercise.setsList.allSatisfy { $0.reps == 8 })
        #expect(row.goals.hasPrefix("ai_coach.routine_draft.rep_goal".localized(8, 12)))
    }

    @Test("A stated rep count is kept inside a stated range")
    func statedRepsStayInsideTheRange() async throws {
        let (exercise, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 15, weight: 60, repRange: (8, 12)),
            description: "Push: bench press 3x15, goal 8-12, 60 kg"
        )

        #expect(exercise.setsList.allSatisfy { $0.reps == 12 })
    }

    /// The path the ticket pins end to end: no range in, nil out, and the sheet says
    /// "no rep goal" rather than showing a blank or the text "nil".
    @Test("No stated range persists no goal and reads as an explicit no-goal")
    func absentRangePersistsNoGoal() async throws {
        let (exercise, row) = try await persist(routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60))

        #expect(exercise.targetRepMin == nil)
        #expect(exercise.targetRepMax == nil)
        #expect(!exercise.hasRepRangeGoal)
        #expect(exercise.setsList.allSatisfy { $0.reps == 8 })
        #expect(row.goals.hasPrefix("ai_coach.routine_draft.no_rep_goal".localized))
        #expect(row.goals.range(of: "nil", options: .caseInsensitive) == nil)
        #expect(row.summary.range(of: "nil", options: .caseInsensitive) == nil)
    }

    @Test("A single rep count copied into both ends is not a range")
    func singleCountIsNotARange() async throws {
        let (exercise, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, repRange: (8, 8))
        )

        #expect(exercise.targetRepMin == nil)
        #expect(exercise.targetRepMax == nil)
    }

    @Test("One stated end alone, or a reversed pair, is no goal")
    func incompleteRangeIsNoGoal() {
        let grounder = RoutineDraftGrounder()
        #expect(grounder.repRangeGoal(low: 8, high: 0) == nil)
        #expect(grounder.repRangeGoal(low: 0, high: 12) == nil)
        #expect(grounder.repRangeGoal(low: 12, high: 8) == nil)
        #expect(grounder.repRangeGoal(low: 90, high: 150).map { [$0.min, $0.max] } == [90, 99])
        // The copied span is parsed in Swift: every separator the pattern allows, and
        // nothing from an empty or junk span.
        #expect(grounder.repRangeGoal(span: "8 bis 12").map { [$0.min, $0.max] } == [8, 12])
        #expect(grounder.repRangeGoal(span: "8 to 12").map { [$0.min, $0.max] } == [8, 12])
        #expect(grounder.repRangeGoal(span: "10–15").map { [$0.min, $0.max] } == [10, 15])
        #expect(grounder.repRangeGoal(span: "") == nil)
        #expect(grounder.repRangeGoal(span: "8-8") == nil)
    }

    // MARK: - Rest

    @Test("A stated rest time lands on every set of the exercise")
    func statedRestPersists() async throws {
        let (exercise, row) = try await persist(
            routineDraftEntry("Bench Press", sets: 4, reps: 8, weight: 60, rest: (.seconds, 90)),
            description: "Push: bench press 4 sets of 8 at 60 kg, 90 seconds rest"
        )

        #expect(exercise.setsList.count == 4)
        #expect(exercise.setsList.allSatisfy { $0.restTime == 90 })
        #expect(row.goals.hasSuffix("ai_coach.routine_draft.rest".localized(TimeFormatting.formatRestTime(90))))
    }

    @Test("The model's unit is a hint: the number is converted in Swift and read back against the words")
    func restUnitIsConvertedInSwift() async throws {
        let (exercise, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, rest: (.minutes, 2)),
            description: "Push: bench press 3 Sätze à 8 mit 60 kg, 2 Minuten Pause"
        )
        #expect(exercise.setsList.allSatisfy { $0.restTime == 120 })

        let grounder = RoutineDraftGrounder()
        #expect(grounder.restTime(.minutes, amount: 1.5) == 90)
        #expect(grounder.restTime(.seconds, amount: 2) == 120)
        #expect(grounder.restTime(.minutes, amount: 30) == 30)
        #expect(grounder.restTime(.seconds, amount: 900) == RoutineDraftGrounder.maximumRestTime)
        #expect(grounder.restTime(.unstated, amount: 90) == RoutineDraftGrounder.defaultRestTime)
    }

    // MARK: - Device probe replays (2026-09-27)

    /// "90 Sekunden" came back as 90 *minutes* on every run of the first schema — the
    /// device check showed "Pause 10m" (the cap).
    @Test("90 seconds drafted as 90 minutes is read back as the typed 90 seconds")
    func secondsDraftedAsMinutes() async throws {
        let (exercise, row) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, rest: (.minutes, 90)),
            description: "Push-Test: bench press 3 Sätze à 8 mit 60 kg, 90 Sekunden Pause"
        )
        #expect(exercise.setsList.allSatisfy { $0.restTime == 90 })
        #expect(row.goals.hasSuffix("ai_coach.routine_draft.rest".localized(TimeFormatting.formatRestTime(90))))
    }

    @Test("A clock time drafted as the wrong number is read back from the words")
    func clockTimeIsReadFromTheWords() async throws {
        let (exercise, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, rest: (.seconds, 180)),
            description: "Push: bench press 3x8 60 kg, 1:30 Pause"
        )
        #expect(exercise.setsList.allSatisfy { $0.restTime == 90 })
    }

    @Test("A range the person did not type is no goal; a wrong one is replaced by the one they typed")
    func rangeNotInTheWordsIsNoGoal() async throws {
        let (untyped, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, repRange: (6, 12)),
            description: "Push-Test: bench press 3x8 60kg 90s Pause"
        )
        #expect(untyped.targetRepMin == nil)
        #expect(untyped.targetRepMax == nil)

        // Probe: "3x8-12" drafted as 6–12. The exercise's own words say 8–12.
        let (corrected, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, repRange: (6, 12)),
            description: "Push-Test: bench press 3x8-12 60kg 90s Pause"
        )
        #expect(corrected.targetRepMin == 8)
        #expect(corrected.targetRepMax == 12)

        let (typed, _) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, repRange: (8, 12)),
            description: "Push-Test: bench press 3x8-12 60kg 90s Pause"
        )
        #expect(typed.targetRepMin == 8)
        #expect(typed.targetRepMax == 12)
    }

    /// The span schema's failure mode on a description with no range: junk spans such as
    /// "8-60" or "8 bis 8". None of them was typed, so none becomes a goal.
    @Test("A junk span on a description with no range is no goal")
    func junkSpanIsNoGoal() {
        let figures = RoutineDraftFigures(words: "Push-Test: Bankdrücken 3 Sätze à 8 mit 60 kg, 90 Sekunden Pause")
        let grounder = RoutineDraftGrounder()
        for junk in ["8-60", "8 bis 8", "8-2", "0-2", "5 bis 5"] {
            #expect(grounder.repRangeGoal(span: junk, figures: figures) == nil, "\(junk)")
        }
    }

    @Test("A rest time copied into the load is no load")
    func restCopiedIntoTheLoadIsDropped() async throws {
        let (exercise, row) = try await persist(
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 2, rest: (.minutes, 2)),
            description: "Push: bench press 3 Sätze à 8, 2 Minuten Pause"
        )
        #expect(exercise.setsList.allSatisfy { $0.weight == 0 && $0.restTime == 120 })
        #expect(!row.summary.contains("kg"))
    }

    @Test("No stated rest falls back to the 60 s default")
    func unstatedRestDefaults() async throws {
        let (exercise, _) = try await persist(routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60))

        #expect(RoutineDraftGrounder.defaultRestTime == 60)
        #expect(exercise.setsList.allSatisfy { $0.restTime == RoutineDraftGrounder.defaultRestTime })
    }

    // MARK: - Editing

    @Test("The set editor opens on the drafted goal and rest, and an edit replaces both")
    func editorCarriesGoalAndRest() async throws {
        let harness = RoutineDraftHarness.make(libraryNames: ["Bench Press"])
        harness.drafting.snapshots = [routineDraftSnapshot(name: "Push", [
            routineDraftEntry("Bench Press", sets: 3, reps: 8, weight: 60, repRange: (8, 12), rest: (.seconds, 90)),
        ])]
        harness.viewModel.onAppear(weightUnit: .kilograms)
        harness.viewModel.descriptionText = "Push: bench press 3 sets of 8-12 at 60 kg, 90 seconds rest"
        harness.viewModel.submit()
        await harness.settle()

        let row = try #require(harness.viewModel.rows.first)
        let seeded = try #require(harness.viewModel.configuration(for: row.id))
        #expect(seeded.targetRepMin == 8)
        #expect(seeded.targetRepMax == 12)
        #expect(seeded.sets.allSatisfy { $0.restTime == 90 })

        harness.viewModel.updateConfiguration(
            row.id,
            sets: (0..<3).map { ExerciseSet(reps: 8, weight: 60, restTime: 0, order: $0) },
            alternatives: [],
            targetRepMin: nil,
            targetRepMax: nil
        )
        let edited = try #require(harness.viewModel.rows.first)
        #expect(edited.goals == [
            "ai_coach.routine_draft.no_rep_goal".localized,
            "ai_coach.routine_draft.rest_off".localized,
        ].joined(separator: " • "))

        harness.viewModel.createRoutine()
        let written = try #require(harness.routines.createdExercises.first?.first)
        #expect(written.targetRepMin == nil)
        #expect(written.sets.allSatisfy { $0.restTime == 0 })
    }
}
