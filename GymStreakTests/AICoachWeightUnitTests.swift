//
//  AICoachWeightUnitTests.swift
//  GymStreakTests
//
//  The AI coach was the last surface in the app still speaking kilograms at a pounds
//  reader — frequently on the same screen as a converted figure, which reads as a bug
//  and undermines trust in the coach's numbers (weight-unit ticket 05).
//
//  What these tests pin is the *boundary*: every weight the model is handed is converted
//  exactly once, from the canonical kilograms, at the point the string is made; the
//  instructions name the same unit the figures are in; and the two sentences Swift
//  composes itself read in the reader's unit. **They cannot pin adherence** — whether
//  the model then writes "lb" rather than "kg" is a device check, recorded in
//  docs/weight-unit-preference.md §13.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct AICoachWeightUnitTests {

    // MARK: - The vocabulary

    @Test("A weight is converted once and rounded to the unit's own precision")
    func vocabularyConvertsAndRounds() {
        // 100 kg is 220.46226… lb; pounds display one decimal.
        #expect(AICoachUnitVocabulary.compact(100, in: .pounds) == "220.5")
        #expect(AICoachUnitVocabulary.compact(100, in: .kilograms) == "100")
        #expect(AICoachUnitVocabulary.compact(87.5, in: .kilograms) == "87.5")
    }

    /// `%g` was the obvious rendering and it is wrong: its six significant digits turn a
    /// real all-time tonnage into `1.23457e+06`, which the chat's volume fact line would
    /// have handed straight to the model.
    @Test("A tonnage renders as digits, never in scientific notation")
    func vocabularyNeverRendersScientificNotation() {
        let line = AICoachUnitVocabulary.compact(1_234_567.8, in: .kilograms)
        #expect(!line.contains("e+"))
        #expect(line.hasPrefix("1234567"))
    }

    @Test("The unit word and the labelled phrase follow the reader's unit and locale")
    func vocabularyLabelsInTheReadersConvention() {
        let german = Locale(identifier: "de_DE")
        #expect(AICoachUnitVocabulary.unitWord(.pounds) == "lb")
        #expect(AICoachUnitVocabulary.unitWord(.kilograms) == "kg")
        #expect(AICoachUnitVocabulary.labelled(20, in: .kilograms, locale: german) == "20,0 kg")
        #expect(AICoachUnitVocabulary.labelled(20, in: .pounds, locale: german) == "44,1 lb")
    }

    // MARK: - Post-workout recap

    @Test("The post-workout prompt and its instructions name one and the same unit")
    func postWorkoutPromptAndInstructionsAgree() {
        let input = PostWorkoutRecapInput(
            locale: "en_US",
            workoutVolumeKg: 5_000,
            totalSets: 20,
            durationMinutes: 60,
            muscleGroupsTrained: [
                MuscleGroupSummary(name: "Chest", volumeKg: 2_000, percentVsFourWeekAverage: 12)
            ],
            newPRs: [PRSummary(exerciseName: "Dip", weightKg: 100, reps: 5)],
            sessionsThisWeek: 3
        )

        let pounds = input.toPromptText(in: .pounds)
        #expect(pounds.contains("220.5 lb"))          // the PR set
        #expect(pounds.contains("11023.1 lb"))        // the workout's volume
        #expect(!pounds.contains(" kg"))

        // The instructions teach the model to echo the input's unit word verbatim, so
        // they have to carry the same one — the "87.5 kg → 87.5 kg" example is exactly
        // how a kilogram literal would teach it to write the wrong word.
        let instructions = PostWorkoutRecapInstructions.systemPrompt(unit: .pounds)
        #expect(instructions.contains("87.5 lb"))
        #expect(instructions.contains("pounds (lb)"))
        #expect(!instructions.contains("kg"))

        let kilograms = input.toPromptText(in: .kilograms)
        #expect(kilograms.contains("100.0 kg"))
        #expect(!kilograms.contains("lb"))
    }

    // MARK: - Workout analysis

    @Test("Workout-analysis fact lines and the composed headline read in the reader's unit")
    func workoutAnalysisConvertsFactsAndHeadline() {
        let input = WorkoutAnalysisInput(
            locale: "en_US",
            routineName: "Push",
            daysSincePrevious: 7,
            currentDurationMinutes: 60,
            currentTotalSets: 6,
            currentCompletionPercentage: 100,
            previousTotalSets: 6,
            droppedExerciseCount: 0,
            exercises: [
                WorkoutAnalysisExerciseInput(
                    exerciseName: "Dip",
                    isFirstTime: false,
                    sets: [
                        WorkoutAnalysisSetInput(
                            setNumber: 1,
                            currentWeightKg: 100,
                            currentReps: 5,
                            isCompleted: true,
                            previousWeightKg: 90,
                            previousReps: 5
                        )
                    ]
                )
            ],
            newPRs: [PRSummary(exerciseName: "Dip", weightKg: 100, reps: 5)]
        )

        let pounds = input.toPromptText(in: .pounds)
        #expect(pounds.contains("220.5 lb x 5 reps"))
        // The delta is converted too — 10 kg is 22.0 lb, not 10 lb next to a pound figure.
        #expect(pounds.contains("+22 lb"))
        #expect(!pounds.contains("kg"))

        // App-authored copy, drawn above the model's paragraphs.
        #expect(input.headlineSentence(in: .pounds).contains("220.5 lb"))
        #expect(input.headlineSentence(in: .kilograms).contains("100 kg"))

        // The German example patterns are copied almost verbatim by the model, so they
        // carry the active unit rather than a hardcoded "kg".
        let instructions = WorkoutAnalysisInstructions.systemPrompt(unit: .pounds)
        #expect(instructions.contains("Topsatz 2,5 lb schwerer"))
        #expect(!instructions.contains("kg"))
    }

    // MARK: - Exercise deep dive

    @Test("The deep-dive prompt and its peak sentence read in the reader's unit")
    func deepDiveConvertsProgressionAndPeak() {
        let input = ExerciseDeepDiveInput(
            locale: "de_DE",
            exerciseName: "Biceps Curls",
            usageLabel: nil,
            blendedUsageCount: 1,
            totalSessions: 15,
            historyRange: "Juli 2026 – August 2026",
            overallProgression: ProgressionSummary(estimatedOneRMDeltaKg: 4.0, percentChange: 18),
            peak: PerformancePoint(
                weightKg: 20.0,
                reps: 6,
                estimatedOneRMKg: 24.0,
                monthLabel: "August 2026"
            ),
            strongestSegment: nil,
            currentSegment: nil
        )

        // 4 kg → 8.8 lb, in the reader's own decimal convention so the model only copies.
        let prompt = input.toPromptText(in: .pounds)
        #expect(prompt.contains("Estimated 1RM change: +8,8 lb"))
        #expect(!prompt.contains("kg"))

        // The sentence sits directly under a chart headline that already says "44,1 lb".
        let peak = input.peakSentence(in: .pounds)
        #expect(peak.contains("44,1 lb"))
        #expect(peak.contains("52,9 lb"))
        #expect(!peak.contains("kg"))
        #expect(!peak.contains("ai_coach.deep_dive.peak"))

        #expect(input.peakSentence(in: .kilograms).contains("20,0 kg"))
    }

    // MARK: - Chat

    @Test("The chat's ambient unit line names the active unit")
    func chatInstructionsNameTheActiveUnit() {
        let pounds = CoachChatInstructions.build(digest: nil, unit: .pounds)
        #expect(pounds.contains("All weights are in pounds (lb)."))
        #expect(!pounds.contains("kilograms"))

        let kilograms = CoachChatInstructions.build(digest: nil, unit: .kilograms)
        #expect(kilograms.contains("All weights are in kilograms (kg)."))
    }

    // MARK: - Output guides

    /// `@Guide(description:)` is a literal in a *static* generation schema, so it cannot
    /// carry a per-reader unit — and a guide hardcoding "kg" is what told the model to
    /// write kilograms while it was being handed pounds. The guides now say "copy it".
    @Test("No output guide instructs the model to emit kilograms")
    func outputGuidesNameNoUnit() {
        let schemas = [
            String(describing: PeriodRecapOutput.generationSchema),
            String(describing: WorkoutAnalysisOutput.generationSchema),
            String(describing: ExerciseDeepDiveOutput.generationSchema),
            String(describing: PostWorkoutRecapOutput.generationSchema)
        ]

        // Positive control first. Every assertion below is a `!contains`, so if
        // `GenerationSchema`'s description ever stopped surfacing `@Guide` descriptions
        // they would all pass while pinning nothing — which is precisely the regression
        // this test exists to catch. These two phrases live in the guides being checked.
        #expect(schemas[0].contains("Detected patterns"))
        #expect(schemas[1].contains("COPY THE EXERCISE NAME FROM THE INPUT EXACTLY"))

        for schema in schemas {
            #expect(!schema.contains("in kg"))
            #expect(!schema.contains("kg gains"))
        }
    }

    // MARK: - Significance thresholds

    /// The aggregators decide whether a change is worth mentioning with bare kilogram
    /// magnitudes (0.5 kg per session / per segment). Those are judgements about real
    /// progress, so they are applied to the canonical values *before* anything converts —
    /// comparing a pounds delta against a kilogram bar would silently more than double it.
    @Test("A segment's stable/improving cut-off is a kilogram magnitude, not a display one")
    func segmentClassificationIsUnitIndependent() {
        // 0.7 kg is above the 0.5 kg bar in kilograms and stays above it in pounds; the
        // rendered magnitude is what differs, never the verdict.
        let input = ExerciseDeepDiveInput(
            locale: "en_US",
            exerciseName: "Row",
            usageLabel: nil,
            blendedUsageCount: 1,
            totalSessions: 8,
            historyRange: "July 2026 – August 2026",
            overallProgression: ProgressionSummary(estimatedOneRMDeltaKg: 0.7, percentChange: 2),
            peak: PerformancePoint(weightKg: 40, reps: 8, estimatedOneRMKg: 50, monthLabel: "August 2026"),
            strongestSegment: ProgressionSegment(
                classification: "improving",
                range: "July 2026",
                avgSessionsPerWeek: 2.0,
                magnitude: "+1.5 lb est. 1RM"
            ),
            currentSegment: nil
        )
        let prompt = input.toPromptText(in: .pounds)
        #expect(prompt.contains("Classification: improving"))
        #expect(prompt.contains("+1.5 lb est. 1RM"))
        #expect(prompt.contains("Estimated 1RM change: +1.5 lb"))
    }
}
