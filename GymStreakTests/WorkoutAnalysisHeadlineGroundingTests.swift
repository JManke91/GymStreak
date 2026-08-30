//
//  WorkoutAnalysisHeadlineGroundingTests.swift
//  GymStreakTests
//
//  Measured on device, German, 2026-08-29: the coach headline read "Neuer Bestwert bei
//  Bankdrücken: 16 kg x 7 Wiederholungen." for a session in which Bankdrücken was not
//  trained at all — the routine's Bankdrücken slot had been swapped for its alternative
//  Flying Chest, and the figures belonged to Dip's real PR. "Bankdrücken" existed in
//  exactly one place: the worked headline example inside the system prompt, which the
//  same prompt's "translate every word into the target language" rule invited the model
//  to reach for in place of the English name "Dip".
//
//  These tests pin the structure that replaced that arrangement: the headline is composed
//  in Swift and no longer a generated field, and the prompt no longer carries an exercise
//  name for a model to borrow. **They cannot pin adherence** — what the model writes into
//  the fields it still owns is a device check.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct WorkoutAnalysisHeadlineGroundingTests {

    // MARK: - Fixtures

    /// The shape of the session that produced the wrong headline: a swapped-in alternative
    /// that matched its last session, and a different exercise that set the PR.
    private func makeInput(
        locale: String = "de_DE",
        newPRs: [PRSummary] = [PRSummary(exerciseName: "Dip", weightKg: 16, reps: 7)],
        exercises: [WorkoutAnalysisExerciseInput]? = nil
    ) -> WorkoutAnalysisInput {
        WorkoutAnalysisInput(
            locale: locale,
            routineName: "Push",
            daysSincePrevious: 7,
            currentDurationMinutes: 103,
            currentTotalSets: 18,
            currentCompletionPercentage: 100,
            previousTotalSets: 18,
            droppedExerciseCount: 0,
            exercises: exercises ?? [
                makeExercise(name: "Flying Chest", weight: 40, reps: 6, previousWeight: 40, previousReps: 6),
                makeExercise(name: "Dip", weight: 16, reps: 7, previousWeight: 16, previousReps: 5)
            ],
            newPRs: newPRs
        )
    }

    private func makeExercise(
        name: String,
        weight: Double,
        reps: Int,
        previousWeight: Double?,
        previousReps: Int?
    ) -> WorkoutAnalysisExerciseInput {
        WorkoutAnalysisExerciseInput(
            exerciseName: name,
            isFirstTime: false,
            sets: [
                WorkoutAnalysisSetInput(
                    setNumber: 1,
                    currentWeightKg: weight,
                    currentReps: reps,
                    isCompleted: true,
                    previousWeightKg: previousWeight,
                    previousReps: previousReps
                )
            ]
        )
    }

    // MARK: - The headline never passes through the model

    @Test("The PR headline names the exercise that set the PR, with its own figures")
    func headlineNamesThePRExercise() {
        let headline = makeInput().headlineSentence(in: .kilograms)

        #expect(headline.contains("Dip"))
        #expect(headline.contains("16"))
        #expect(headline.contains("7"))
        // The exact substitution that shipped: a name from nowhere in the session.
        #expect(!headline.contains("Bankdrücken"))
        // The template resolved — an unresolved key would come back as the key itself.
        #expect(!headline.contains("ai_coach.workout_analysis.headline"))
    }

    @Test("A second PR is counted, not silently dropped")
    func headlineCountsFurtherPRs() {
        let headline = makeInput(newPRs: [
            PRSummary(exerciseName: "Dip", weightKg: 16, reps: 7),
            PRSummary(exerciseName: "Overhead Triceps", weightKg: 21.5, reps: 12)
        ]).headlineSentence(in: .kilograms)

        #expect(headline.contains("Dip"))
        #expect(headline.contains("1"))
        #expect(!headline.contains("ai_coach.workout_analysis.headline"))
    }

    @Test("Without a PR the headline states the improved/total counts")
    func headlineFallsBackToCounts() {
        let headline = makeInput(
            newPRs: [],
            exercises: [
                makeExercise(name: "Flying Chest", weight: 40, reps: 6, previousWeight: 40, previousReps: 6),
                makeExercise(name: "Dip", weight: 16, reps: 7, previousWeight: 16, previousReps: 5)
            ]
        ).headlineSentence(in: .kilograms)

        // One of two improved, the other unchanged.
        #expect(headline.contains("1"))
        #expect(headline.contains("2"))
        #expect(!headline.contains("ai_coach.workout_analysis.headline"))
    }

    @Test("Weights read in the locale's decimal notation, without a trailing zero")
    func headlineFormatsWeightForTheReader() {
        let german = makeInput(newPRs: [PRSummary(exerciseName: "Dip", weightKg: 82.5, reps: 5)]).headlineSentence(in: .kilograms)
        #expect(german.contains("82,5"))

        let english = makeInput(
            locale: "en_US",
            newPRs: [PRSummary(exerciseName: "Dip", weightKg: 82.5, reps: 5)]
        ).headlineSentence(in: .kilograms)
        #expect(english.contains("82.5"))

        // A whole number stays whole — "16 kg", never "16,0 kg".
        #expect(makeInput().headlineSentence(in: .kilograms).contains("16,0") == false)
    }

    @Test("The model has no headline field to write")
    func headlineIsNotGenerated() {
        let schema = String(describing: WorkoutAnalysisOutput.generationSchema)

        // A property, not the word — `closingObservation`'s guide mentions the headline
        // to forbid restating it.
        #expect(!schema.contains("\"headline\""))
        #expect(schema.contains("\"exerciseHighlights\""))
        #expect(schema.contains("\"closingObservation\""))
    }

    // MARK: - Nothing in the prompt supplies an exercise name

    /// Apple's *Prompting an on-device foundation model*: "overly long or complex examples
    /// can lead to repetition or hallucination", and a prompt should be one to three
    /// paragraphs. Both symptoms shipped from one example line, so there is no example.
    @Test("No example exercise name remains in the instructions")
    func instructionsCarryNoExampleExerciseName() {
        let prompt = WorkoutAnalysisInstructions.systemPrompt(unit: .kilograms)

        #expect(!prompt.contains("Bankdrücken"))
        // The translate-everything rule now carves exercise names out explicitly.
        #expect(prompt.contains("EXERCISE NAMES ARE THE ONE EXCEPTION"))
    }

    @Test("The name-copy rule sits on the field that carries the name")
    func highlightGuideCarriesTheCopyRule() {
        let schema = String(describing: WorkoutAnalysisOutput.generationSchema)

        #expect(schema.contains("COPY THE EXERCISE NAME FROM THE INPUT EXACTLY"))
        #expect(schema.contains("NAME ONLY EXERCISES THAT APPEAR IN THE INPUT"))
    }

    @Test("The session summary reaches the prompt as context, not as a headline order")
    func promptStatesTheSummaryAsContext() {
        let prompt = makeInput().toPromptText(in: .kilograms)

        #expect(prompt.contains("Session summary:"))
        #expect(!prompt.contains("Headline fact:"))
        // The PR still crosses over — the PR highlight has to state that set.
        #expect(prompt.contains("Dip: 16 kg x 7 reps"))
    }
}
