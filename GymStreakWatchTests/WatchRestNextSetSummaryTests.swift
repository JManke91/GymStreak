//
//  WatchRestNextSetSummaryTests.swift
//  GymStreakWatchTests
//
//  `WatchRestNextSetSummary` is what the rest timer's caption slot says while a
//  rest runs. It is deliberately pure — the view model that supplies its inputs
//  has no coverage of its own — so this is the only place the next-set line's
//  formatting, its unit handling and its bodyweight case are ever asserted.
//
//  Weights are canonical kilograms in, display strings out.
//
//  ASSERT NOTHING AGAINST AN ENGLISH LITERAL HERE. The watch test destination
//  runs in German, so every localized fragment — the reps word, the "Next set"
//  announcement, the spoken unit, and the decimal separator inside a converted
//  weight — comes back translated. Expectations are therefore either composed
//  from the same seam the code uses, or restricted to the parts that are
//  language-independent: the digits, the "×", and the "kg"/"lb" unit words,
//  which are the same in both languages.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchRestNextSetSummaryTests {

    // MARK: - Reading the right set

    @Test("The next set of the same exercise reads that set's own target")
    func nextSetInSameExercise() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60), (reps: 8, kilograms: 80)])
        ]

        let summary = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 0,
            setIndex: 1,
            unit: .kilograms
        )

        #expect(summary?.display == "80 kg × 8")
    }

    @Test("A next set that lives in a following exercise is read from that exercise")
    func nextSetInFollowingExercise() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)]),
            makeExercise(name: "Cable Row", sets: [(reps: 12, kilograms: 45)])
        ]

        let summary = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 1,
            setIndex: 0,
            unit: .kilograms
        )

        #expect(summary?.display == "45 kg × 12")
    }

    /// A superset rotates back to a *previous* exercise between sets, so the
    /// coordinates the view model hands over can move backwards as well as
    /// forwards. Nothing here special-cases that — which is the assertion.
    @Test("A superset rotation back to an earlier exercise reads its next set")
    func nextSetInSupersetRotation() {
        let supersetID = UUID()
        let exercises = [
            makeExercise(
                name: "Bench Press",
                sets: [(reps: 10, kilograms: 60), (reps: 10, kilograms: 62.5)],
                supersetID: supersetID,
                supersetOrder: 0
            ),
            makeExercise(
                name: "Cable Row",
                sets: [(reps: 12, kilograms: 45), (reps: 12, kilograms: 45)],
                supersetID: supersetID,
                supersetOrder: 1
            )
        ]

        // Resting after Cable Row set 1: the rotation goes back to Bench Press.
        let summary = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 0,
            setIndex: 1,
            unit: .kilograms
        )

        // Composed, not literal: 62.5 carries a decimal separator and that one
        // is the test locale's.
        #expect(summary?.display == "\(WatchWeightFormatting.number(62.5, in: .kilograms)) kg × 10")
    }

    // MARK: - Units

    @Test("The weight is converted to the display unit, never re-derived from the locale")
    func poundsConvertFromCanonicalKilograms() {
        let exercises = [makeExercise(name: "Squat", sets: [(reps: 5, kilograms: 100)])]

        let kilograms = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 0, unit: .kilograms
        )
        let pounds = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 0, unit: .pounds
        )

        #expect(kilograms?.display == "100 kg × 5")
        #expect(pounds?.display == "\(WatchWeightFormatting.number(100, in: .pounds)) lb × 5")
        #expect(pounds?.display != kilograms?.display)
    }

    // MARK: - Bodyweight

    @Test("A bodyweight set shows its reps only, never \"0 kg\"")
    func bodyweightShowsRepsOnly() {
        let exercises = [makeExercise(name: "Pull-Up", sets: [(reps: 8, kilograms: 0)])]

        let displays = WeightUnit.allCases.map { unit in
            WatchRestNextSetSummary.target(
                in: exercises, exerciseIndex: 0, setIndex: 0, unit: unit
            )?.display
        }

        for display in displays {
            #expect(display?.contains("8") == true)
            // No weight, so no unit word and nothing for the "×" to separate.
            #expect(display?.contains("×") == false)
            for unit in WeightUnit.allCases {
                #expect(display?.contains(WatchWeightFormatting.unitWord(unit)) == false)
            }
        }
        // Identical in both units: there is no weight to convert.
        #expect(displays[0] == displays[1])
    }

    // MARK: - VoiceOver

    @Test("The spoken form names the set, spells the unit out and keeps the reps word")
    func spokenFormSpellsTheUnitOut() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 8, kilograms: 80), (reps: 8, kilograms: 0)])
        ]

        let weighted = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 0, unit: .kilograms
        )
        #expect(weighted?.spoken.contains(String(localized: "Next set")) == true)
        #expect(weighted?.spoken.contains("80") == true)
        // "kay gee" is what this exists to avoid: the spoken unit word, not "kg".
        #expect(weighted?.spoken.contains(WatchWeightFormatting.spokenUnitWord(.kilograms)) == true)
        #expect(weighted?.spoken.contains(WatchWeightFormatting.unitWord(.kilograms)) == false)
        // The "×" of the written line reads as nothing at all through VoiceOver.
        #expect(weighted?.spoken.contains("×") == false)

        let bodyweight = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 1, unit: .kilograms
        )
        #expect(bodyweight?.spoken.contains(String(localized: "Next set")) == true)
        #expect(bodyweight?.spoken.hasSuffix(bodyweight?.display ?? "") == true)
    }

    // MARK: - Out of range

    @Test("Indices outside the workout yield nil rather than a placeholder line")
    func outOfRangeIndicesReturnNil() {
        let exercises = [makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)])]

        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 1, setIndex: 0, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 1, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: -1, setIndex: 0, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: -1, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: [], exerciseIndex: 0, setIndex: 0, unit: .kilograms
        ) == nil)
        // An exercise whose sets were all removed — the same guard, one level in.
        #expect(WatchRestNextSetSummary.target(
            in: [makeExercise(name: "Empty", sets: [])],
            exerciseIndex: 0,
            setIndex: 0,
            unit: .kilograms
        ) == nil)
    }

    // MARK: - Fixtures

    private func makeExercise(
        name: String,
        sets: [(reps: Int, kilograms: Double)],
        supersetID: UUID? = nil,
        supersetOrder: Int = 0
    ) -> ActiveWorkoutExercise {
        ActiveWorkoutExercise(
            id: UUID(),
            name: name,
            muscleGroup: "General",
            sets: sets.enumerated().map { index, set in
                ActiveWorkoutSet(
                    id: UUID(),
                    plannedReps: set.reps,
                    actualReps: set.reps,
                    plannedWeight: set.kilograms,
                    actualWeight: set.kilograms,
                    restTime: 60,
                    completedAt: nil,
                    order: index
                )
            },
            order: 0,
            supersetId: supersetID,
            supersetOrder: supersetOrder,
            exerciseId: UUID()
        )
    }
}
