//
//  CoachPromptFigureLocaleTests.swift
//  GymStreakTests
//
//  **A figure the model is told to copy must already be the figure the reader should see.**
//
//  Every narrating coach prompt tells the model to copy each figure "digit for digit,
//  including its decimal separator" (docs/ai-coach.md § "Prompt grounding rules", rule 1),
//  and it obeys. Prompt figures were rendered in the C locale, so on device (German,
//  2026-08-30) the post-workout recap wrote "ein Gesamtvolumen von 1830.0 kg" and the
//  Rückblick wrote "+10.0 kg geschätztes 1RM" and "2.0 Einheiten pro Woche" — English
//  decimal points inside German sentences.
//
//  The assertion throughout is the absence of a period between two digits. In a German
//  prompt that can only be a decimal point: `AICoachUnitVocabulary.fixed` never emits a
//  grouping separator, deliberately, because German groups with the period and separates
//  decimals with the comma — `1.830,0` would put *two* locale-dependent characters into a
//  string the model copies character for character.
//
//  **Its own file rather than an addition to `AICoachWeightUnitTests`**, which owns the
//  unit vocabulary and is already 280 lines: this is one invariant across four surfaces,
//  two of which need a `ModelContext`, and both files stay under the size convention.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct CoachPromptFigureLocaleTests {

    /// `1.5`, `20.08` — a period between two digits. Never legitimate in a German prompt.
    private func englishDecimals(in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"\d\.\d"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }

    private func expectNoEnglishDecimal(_ prompt: String, _ surface: String) throws {
        let hits = try englishDecimals(in: prompt)
        #expect(hits.isEmpty, "\(surface) writes an English decimal point \(hits) in a German prompt:\n\(prompt)")
    }

    // MARK: - Post-workout recap — "ein Gesamtvolumen von 1830.0 kg"

    @Test("The post-workout prompt writes German figures with a comma")
    func postWorkoutFiguresFollowTheReader() throws {
        for unit in WeightUnit.allCases {
            try expectNoEnglishDecimal(
                Self.postWorkoutInput(locale: "de_DE").toPromptText(in: unit),
                "post-workout recap (\(unit.rawValue))"
            )
        }
    }

    /// The rule is "the reader's separator", not "always a comma" — and never a grouping
    /// separator, which `String(format:locale:)` would have added.
    @Test("The post-workout prompt keeps the period for an English reader")
    func postWorkoutFiguresKeepThePeriodInEnglish() {
        let prompt = Self.postWorkoutInput(locale: "en_US").toPromptText(in: .kilograms)
        #expect(prompt.contains("1830.0 kg"))
        #expect(!prompt.contains("1830,0"))
        #expect(!prompt.contains("1,830"))
    }

    // MARK: - Workout analysis

    @Test("The workout-analysis prompt writes German figures with a comma")
    func workoutAnalysisFiguresFollowTheReader() throws {
        for unit in WeightUnit.allCases {
            try expectNoEnglishDecimal(
                Self.workoutAnalysisInput().toPromptText(in: unit),
                "workout analysis (\(unit.rawValue))"
            )
        }
    }

    // MARK: - Exercise deep-dive — the surface that always did this correctly

    @Test("The deep-dive prompt writes German figures with a comma")
    func deepDiveFiguresFollowTheReader() throws {
        try expectNoEnglishDecimal(
            Self.deepDiveInput().toPromptText(in: .kilograms),
            "exercise deep dive"
        )
    }

    // MARK: - Period recap — "2.0 Einheiten pro Woche"

    /// The consistency line is rendered inside `PeriodRecapInput.toPromptText()`, so a
    /// plain fixture pins it.
    @Test("The period-recap consistency line writes sessions per week with a comma")
    func periodRecapConsistencyLineFollowsTheReader() throws {
        try expectNoEnglishDecimal(
            Self.periodRecapInput().toPromptText(),
            "period recap consistency line"
        )
    }

    /// **The trend magnitude needs the aggregator, not a fixture.** `TrendFinding.magnitude`
    /// is a *stored* string that `toPromptText` echoes verbatim, so a hand-written fixture
    /// would only assert on itself. `+10.0 kg geschätztes 1RM` — the figure the tester
    /// actually saw — is composed in `PeriodRecapAggregator.buildTrends`, and this is the
    /// only test that reaches it.
    @Test("The period-recap trend magnitude is composed with the reader's separator")
    func periodRecapTrendMagnitudeFollowsTheReader() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let press = Exercise(name: "Schulterpresse", equipmentType: .barbell)
        context.insert(press)

        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        // Three sessions clears the insufficient-data gate; a climbing load makes the
        // exercise "improved", which is what carries a signed magnitude.
        for (day, weight) in [(5, 20.0), (10, 25.0), (15, 30.0)] {
            let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: day)))
            Self.addSession(exercise: press, weight: weight, reps: 5, at: start, in: context)
        }
        try context.save()

        let input = PeriodRecapAggregator().buildInput(
            range: .thisMonth,
            locale: Locale(identifier: "de_DE"),
            modelContext: context,
            weightUnit: .kilograms,
            now: now
        )

        #expect(!input.isInsufficient)
        let magnitudes = input.trends.map(\.magnitude)
        #expect(!magnitudes.isEmpty, "no trend was produced, so nothing was pinned")
        for magnitude in magnitudes {
            #expect(try englishDecimals(in: magnitude).isEmpty,
                    "trend magnitude '\(magnitude)' carries an English decimal point")
        }
        try expectNoEnglishDecimal(input.toPromptText(), "period recap prompt")
    }

    /// The same aggregation for an English reader keeps the period — proving the test
    /// above pins the reader's convention and not merely "a comma somewhere".
    @Test("The period-recap trend magnitude keeps the period for an English reader")
    func periodRecapTrendMagnitudeKeepsThePeriodInEnglish() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let press = Exercise(name: "Shoulder Press", equipmentType: .barbell)
        context.insert(press)

        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        for (day, weight) in [(5, 20.0), (10, 25.0), (15, 30.0)] {
            let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: day)))
            Self.addSession(exercise: press, weight: weight, reps: 5, at: start, in: context)
        }
        try context.save()

        let input = PeriodRecapAggregator().buildInput(
            range: .thisMonth,
            locale: Locale(identifier: "en_US"),
            modelContext: context,
            weightUnit: .kilograms,
            now: now
        )
        let magnitudes = input.trends.map(\.magnitude)
        #expect(!magnitudes.isEmpty)
        #expect(magnitudes.contains { $0.contains(".") })
        #expect(!magnitudes.contains { $0.contains(",") })
    }

    // MARK: - Fixtures

    private static func postWorkoutInput(locale: String) -> PostWorkoutRecapInput {
        PostWorkoutRecapInput(
            locale: locale,
            workoutVolumeKg: 1_830,
            totalSets: 20,
            durationMinutes: 32,
            muscleGroupsTrained: [
                MuscleGroupSummary(name: "Schultern", volumeKg: 457.5, percentVsFourWeekAverage: 75)
            ],
            newPRs: [PRSummary(exerciseName: "Arnold Press", weightKg: 45.5, reps: 8)],
            sessionsThisWeek: 3
        )
    }

    private static func workoutAnalysisInput() -> WorkoutAnalysisInput {
        WorkoutAnalysisInput(
            locale: "de_DE",
            routineName: "Push",
            daysSincePrevious: 3,
            currentDurationMinutes: 32,
            currentTotalSets: 8,
            currentCompletionPercentage: 40,
            previousTotalSets: 8,
            droppedExerciseCount: 0,
            exercises: [
                WorkoutAnalysisExerciseInput(
                    exerciseName: "Arnold Press",
                    isFirstTime: false,
                    sets: [
                        WorkoutAnalysisSetInput(
                            setNumber: 1,
                            currentWeightKg: 45.5,
                            currentReps: 8,
                            isCompleted: true,
                            previousWeightKg: 43,
                            previousReps: 8
                        )
                    ]
                )
            ],
            newPRs: [PRSummary(exerciseName: "Arnold Press", weightKg: 45.5, reps: 8)]
        )
    }

    private static func deepDiveInput() -> ExerciseDeepDiveInput {
        ExerciseDeepDiveInput(
            locale: "de_DE",
            exerciseName: "Biceps Curls",
            usageLabel: "4–6 Wdh. · Pull",
            blendedUsageCount: 1,
            totalSessions: 15,
            historyRange: "Juli 2026 – August 2026",
            overallProgression: ProgressionSummary(estimatedOneRMDeltaKg: 4.5, percentChange: 18),
            peak: PerformancePoint(
                weightKg: 20.5,
                reps: 6,
                estimatedOneRMKg: 24.5,
                monthLabel: "August 2026"
            ),
            strongestSegment: ProgressionSegment(
                classification: "improving",
                range: "Juli 2026 – August 2026",
                avgSessionsPerWeek: 2.5,
                magnitude: "+4,5 kg est. 1RM"
            ),
            currentSegment: ProgressionSegment(
                classification: "plateau",
                range: "August 2026",
                avgSessionsPerWeek: 1.5,
                magnitude: "stable"
            )
        )
    }

    private static func periodRecapInput() -> PeriodRecapInput {
        PeriodRecapInput(
            locale: "de_DE",
            periodLabel: "August 2026",
            headline: HeadlineMetrics(
                totalSessions: 10,
                totalVolumeKg: 35_000,
                averageSessionMinutes: 45,
                distinctExercises: 12
            ),
            consistency: ConsistencyMetrics(
                totalWeeks: 5,
                trainedWeeks: 5,
                averageSessionsPerWeek: 2.0,
                longestGapDays: 6,
                isIrregular: false
            ),
            trends: [
                TrendFinding(subject: "Ausfallschritt", direction: "improved", magnitude: "+10,0 kg")
            ],
            correlations: [],
            recommendationFact: nil,
            isInsufficient: false
        )
    }

    private static func addSession(
        exercise: Exercise,
        weight: Double,
        reps: Int,
        at start: Date,
        in context: ModelContext
    ) {
        let session = WorkoutSession(routine: nil)
        session.startTime = start
        session.endTime = start.addingTimeInterval(2_700)
        context.insert(session)

        let row = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: ["Shoulders"],
            order: 0,
            exerciseId: exercise.id,
            routineExerciseId: nil,
            loadBehavior: exercise.loadBehavior
        )
        row.workoutSession = session
        context.insert(row)

        for index in 0..<3 {
            let set = WorkoutSet(
                plannedReps: reps,
                actualReps: reps,
                plannedWeight: weight,
                actualWeight: weight,
                restTime: 90,
                order: index
            )
            set.isCompleted = true
            set.workoutExercise = row
            context.insert(set)
        }
    }
}
