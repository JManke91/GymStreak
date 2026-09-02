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
            startedAfterExerciseID: nil,
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
            startedAfterExerciseID: nil,
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
            startedAfterExerciseID: nil,
            unit: .kilograms
        )

        // Composed, not literal: 62.5 carries a decimal separator and that one
        // is the test locale's.
        #expect(summary?.display == "\(WatchWeightFormatting.number(62.5, in: .kilograms)) kg × 10")
    }

    // MARK: - Naming the exercise when it changed

    /// The common case, and the one with the strictest bar: another set of the
    /// same exercise must leave the line byte-identical to what it was before
    /// this feature existed.
    @Test("Another set of the same exercise is not named")
    func sameExerciseIsNotNamed() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60), (reps: 8, kilograms: 80)])
        ]

        let named = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 0,
            setIndex: 1,
            startedAfterExerciseID: exercises[0].id,
            unit: .kilograms
        )
        let unknownOrigin = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 0,
            setIndex: 1,
            startedAfterExerciseID: nil,
            unit: .kilograms
        )

        #expect(named?.exerciseName == nil)
        #expect(named == unknownOrigin)
    }

    @Test("A next set in a following exercise names that exercise")
    func nextExerciseIsNamed() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)]),
            makeExercise(name: "Cable Row", sets: [(reps: 12, kilograms: 45)])
        ]

        let summary = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 1,
            setIndex: 0,
            startedAfterExerciseID: exercises[0].id,
            unit: .kilograms
        )

        #expect(summary?.exerciseName == "Cable Row")
        // The name is additive: the target it accompanies is unchanged.
        #expect(summary?.display == "45 kg × 12")
    }

    /// The case this exists for. A superset's rest starts only at the end of a
    /// full round, and the next set is then always the *first* exercise of the
    /// next round — so it is never the exercise just performed, and the name is
    /// the difference between the line being useful and being wrong.
    @Test("A superset round rollover names the next round's exercise")
    func supersetRoundRolloverNamesTheNextExercise() {
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

        // Round 1 ended on Cable Row; the rotation goes back to Bench Press.
        let summary = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 0,
            setIndex: 1,
            startedAfterExerciseID: exercises[1].id,
            unit: .kilograms
        )

        #expect(summary?.exerciseName == "Bench Press")
    }

    /// Compared by id, not index: the cursor can be moved during a rest by
    /// `navigateToNextExercise` or a direct jump, and an index comparison would
    /// then name whatever happens to sit at the old position.
    @Test("A rest whose origin exercise is unknown keeps the unnamed line")
    func unknownOriginKeepsTheUnnamedLine() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)]),
            makeExercise(name: "Cable Row", sets: [(reps: 12, kilograms: 45)])
        ]

        let summary = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 1,
            setIndex: 0,
            startedAfterExerciseID: nil,
            unit: .kilograms
        )

        #expect(summary?.exerciseName == nil)
    }

    /// The comparison is by **id**, and only a reordered array can prove it: in
    /// every other case here the origin's index differs from the cursor's, so an
    /// index comparison would pass them all. Here the origin exercise has moved
    /// **to** the cursor's index — a structural edit mid-workout — and an index
    /// comparison would say "unchanged" while an id comparison correctly names
    /// the exercise that now sits there.
    @Test("A reordered workout is judged by exercise id, not by index")
    func reorderingIsJudgedByIdNotIndex() {
        let bench = makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)])
        let row = makeExercise(name: "Cable Row", sets: [(reps: 12, kilograms: 45)])

        // The rest started after Bench Press, which sat at index 0. Bench Press
        // is now at index 1, and the cursor still points at index 0 — the
        // origin's own former index, now holding a different exercise.
        let reordered = [row, bench]
        let sameIndexDifferentExercise = WatchRestNextSetSummary.target(
            in: reordered,
            exerciseIndex: 0,
            setIndex: 0,
            startedAfterExerciseID: bench.id,
            unit: .kilograms
        )
        #expect(sameIndexDifferentExercise?.exerciseName == "Cable Row")

        // …and the mirror: the origin exercise is now AT the cursor's index, so
        // an index comparison would wrongly name it.
        let sameExerciseDifferentIndex = WatchRestNextSetSummary.target(
            in: reordered,
            exerciseIndex: 1,
            setIndex: 0,
            startedAfterExerciseID: bench.id,
            unit: .kilograms
        )
        #expect(sameExerciseDifferentIndex?.exerciseName == nil)
    }

    /// The name is user data, not a localized string, so the only language
    /// question is width — and width is the view's problem: `WatchMarqueeText`
    /// scrolls the overflow, so nothing here may pre-shorten a name. A long
    /// German compound and a long English one both have to come back whole, in
    /// both display units.
    @Test("A long exercise name is carried verbatim, in either language or unit")
    func longNamesAreCarriedVerbatim() {
        let names = ["Kreuzheben mit gestreckten Beinen", "Barbell Bulgarian Split Squat"]

        for name in names {
            let exercises = [
                makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)]),
                makeExercise(name: name, sets: [(reps: 8, kilograms: 100)])
            ]

            for unit in WeightUnit.allCases {
                let summary = WatchRestNextSetSummary.target(
                    in: exercises,
                    exerciseIndex: 1,
                    setIndex: 0,
                    startedAfterExerciseID: exercises[0].id,
                    unit: unit
                )

                #expect(summary?.exerciseName == name)
                // No ellipsis, no scale hint, no truncation of any kind.
                #expect(summary?.exerciseName?.count == name.count)
                // The name never leaks into the caption's own value.
                #expect(summary?.display.contains(name) == false)
            }
        }
    }

    @Test("The spoken form names the changed exercise before its target")
    func spokenFormNamesTheChangedExercise() {
        let exercises = [
            makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)]),
            makeExercise(name: "Cable Row", sets: [(reps: 12, kilograms: 45)]),
            makeExercise(name: "Pull-Up", sets: [(reps: 8, kilograms: 0)])
        ]

        let weighted = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 1,
            setIndex: 0,
            startedAfterExerciseID: exercises[0].id,
            unit: .kilograms
        )
        #expect(weighted?.spoken.contains("Cable Row") == true)
        // Named first: it is the part a listener cannot infer from the numbers.
        let spoken = weighted?.spoken ?? ""
        let nameRange = spoken.range(of: "Cable Row")
        let weightRange = spoken.range(of: "45")
        #expect(nameRange != nil)
        #expect(weightRange != nil)
        if let nameRange, let weightRange {
            #expect(nameRange.lowerBound < weightRange.lowerBound)
        }

        // Bodyweight, where there is no weight to follow the name.
        let bodyweight = WatchRestNextSetSummary.target(
            in: exercises,
            exerciseIndex: 2,
            setIndex: 0,
            startedAfterExerciseID: exercises[1].id,
            unit: .kilograms
        )
        #expect(bodyweight?.spoken.contains("Pull-Up") == true)
        #expect(bodyweight?.spoken.hasSuffix(bodyweight?.display ?? "") == true)
    }

    // MARK: - Units

    @Test("The weight is converted to the display unit, never re-derived from the locale")
    func poundsConvertFromCanonicalKilograms() {
        let exercises = [makeExercise(name: "Squat", sets: [(reps: 5, kilograms: 100)])]

        let kilograms = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 0, startedAfterExerciseID: nil, unit: .kilograms
        )
        let pounds = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 0, startedAfterExerciseID: nil, unit: .pounds
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
                in: exercises, exerciseIndex: 0, setIndex: 0, startedAfterExerciseID: nil, unit: unit
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
            in: exercises, exerciseIndex: 0, setIndex: 0, startedAfterExerciseID: nil, unit: .kilograms
        )
        #expect(weighted?.spoken.contains(String(localized: "Next set")) == true)
        #expect(weighted?.spoken.contains("80") == true)
        // "kay gee" is what this exists to avoid: the spoken unit word, not "kg".
        #expect(weighted?.spoken.contains(WatchWeightFormatting.spokenUnitWord(.kilograms)) == true)
        #expect(weighted?.spoken.contains(WatchWeightFormatting.unitWord(.kilograms)) == false)
        // The "×" of the written line reads as nothing at all through VoiceOver.
        #expect(weighted?.spoken.contains("×") == false)

        let bodyweight = WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 1, startedAfterExerciseID: nil, unit: .kilograms
        )
        #expect(bodyweight?.spoken.contains(String(localized: "Next set")) == true)
        #expect(bodyweight?.spoken.hasSuffix(bodyweight?.display ?? "") == true)
    }

    // MARK: - Out of range

    @Test("Indices outside the workout yield nil rather than a placeholder line")
    func outOfRangeIndicesReturnNil() {
        let exercises = [makeExercise(name: "Bench Press", sets: [(reps: 10, kilograms: 60)])]

        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 1, setIndex: 0, startedAfterExerciseID: nil, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: 1, startedAfterExerciseID: nil, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: -1, setIndex: 0, startedAfterExerciseID: nil, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: exercises, exerciseIndex: 0, setIndex: -1, startedAfterExerciseID: nil, unit: .kilograms
        ) == nil)
        #expect(WatchRestNextSetSummary.target(
            in: [], exerciseIndex: 0, setIndex: 0, startedAfterExerciseID: nil, unit: .kilograms
        ) == nil)
        // An exercise whose sets were all removed — the same guard, one level in.
        #expect(WatchRestNextSetSummary.target(
            in: [makeExercise(name: "Empty", sets: [])],
            exerciseIndex: 0,
            setIndex: 0,
            startedAfterExerciseID: nil,
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
