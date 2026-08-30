//
//  ExerciseDeepDiveGroundingTests.swift
//  GymStreakTests
//
//  The deep-dive narrative states things its input does not contain, and three rounds of
//  prose rules did not stop it. Measured on device, German, 2026-08-28, freshly
//  generated: "erreicht am 20.08.2026" for an input whose only date was `August 2026`;
//  "in den letzten 6 Monaten" for a `History range` of two months; one undivided block
//  where the instructions asked for three to four paragraphs.
//
//  What tests can pin is the *structure* that replaced those rules — what the model is
//  handed, what shape it has to answer in, and what the app does with the answer.
//  **They cannot pin adherence.** Whether the model obeys the guides it is given is a
//  device check, and this file proves nothing about it.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ExerciseDeepDiveGroundingTests {

    // MARK: - Fixtures

    /// A single-variant input with a two-month history and an August peak — the exact
    /// shape that produced "erreicht am 20.08.2026" and "in den letzten 6 Monaten".
    private func makeInput(
        locale: String = "de_DE",
        blendedUsageCount: Int = 1
    ) -> ExerciseDeepDiveInput {
        let isBlended = blendedUsageCount > 1
        return ExerciseDeepDiveInput(
            locale: locale,
            exerciseName: "Biceps Curls",
            usageLabel: isBlended ? nil : "4–6 Wdh. · Pull",
            blendedUsageCount: blendedUsageCount,
            totalSessions: 15,
            historyRange: locale == "de_DE" ? "Juli 2026 – August 2026" : "July 2026 – August 2026",
            overallProgression: isBlended
                ? nil
                : ProgressionSummary(estimatedOneRMDeltaKg: 4.0, percentChange: 18),
            peak: PerformancePoint(
                weightKg: 20.0,
                reps: 6,
                estimatedOneRMKg: 24.0,
                monthLabel: locale == "de_DE" ? "August 2026" : "August 2026"
            ),
            strongestSegment: isBlended
                ? nil
                : ProgressionSegment(
                    classification: "improving",
                    range: locale == "de_DE" ? "Juli 2026 – August 2026" : "July 2026 – August 2026",
                    avgSessionsPerWeek: 2.0,
                    magnitude: "+4.0 kg est. 1RM"
                ),
            currentSegment: isBlended
                ? nil
                : ProgressionSegment(
                    classification: "plateau",
                    range: locale == "de_DE" ? "August 2026" : "August 2026",
                    avgSessionsPerWeek: 1.5,
                    magnitude: "stable"
                )
        )
    }

    // MARK: - The peak never reaches the model

    /// The one grounding move that has held on this surface is withholding the string
    /// entirely (the variant label). The peak now follows it: the month that got decorated
    /// into `20.08.2026` is composed into a finished sentence in Swift and rendered, so
    /// there is no month in the prompt for a model to make more precise.
    @Test("No peak figure and no peak month reach the prompt")
    func peakIsWithheldFromThePrompt() {
        let prompt = makeInput().toPromptText(in: .kilograms)

        // The peak's own block is gone entirely — label, figures and month.
        #expect(!prompt.contains("When:"))
        #expect(!prompt.contains("peak"))
        #expect(!prompt.contains("Peak"))
        // Months still reach the model through the history range and the segment periods,
        // which are the periods it is meant to name. What has gone is the peak's own
        // month — the one it decorated into a day.
        #expect(!prompt.contains("20,0"))
        #expect(!prompt.contains("24,0"))
        #expect(!prompt.contains("× 6 reps"))
    }

    /// A blended view holds nothing but the workload — so its prompt has no month at all.
    @Test("A blended prompt carries no month beyond the history range")
    func blendedPromptCarriesNoPeak() {
        let prompt = makeInput(blendedUsageCount: 3).toPromptText(in: .kilograms)

        #expect(prompt.contains("BLENDED VIEW"))
        #expect(!prompt.contains("20,0"))
        #expect(!prompt.contains("Peak"))
        // The only period it names is the history range.
        #expect(prompt.contains("Juli 2026 – August 2026"))
    }

    /// Every date in the prompt is a month or a month range. A day anywhere is the bug
    /// this ticket exists for, arriving from the other direction.
    @Test("The prompt contains no date more precise than a month")
    func promptCarriesNoDayLevelDate() throws {
        for locale in ["de_DE", "en_US"] {
            let prompt = makeInput(locale: locale).toPromptText(in: .kilograms)
            // `20.08.2026`, `2026-08-20`, `08/20/2026` — any day-level date form.
            let dayForms = try NSRegularExpression(
                pattern: #"\d{1,4}[./-]\d{1,2}[./-]\d{2,4}"#
            )
            let matches = dayForms.numberOfMatches(
                in: prompt,
                range: NSRange(prompt.startIndex..., in: prompt)
            )
            #expect(matches == 0, "\(locale) prompt carries a day-level date:\n\(prompt)")
        }
    }

    // MARK: - Labels the model copied as if they were data

    /// Handed `Avg sessions/week: 1.3`, the model wrote *"1,3 Wochen pro Sitzung"* — the
    /// ratio inverted. The direction is now spelled out in the prompt rather than left to
    /// be worked out from a label.
    @Test("Training frequency is spelled out, not left as a bare ratio")
    func frequencyCarriesItsDirection() {
        let prompt = makeInput().toPromptText(in: .kilograms)

        #expect(prompt.contains("Training frequency: 2,0 sessions per week"))
        #expect(prompt.contains("Training frequency: 1,5 sessions per week"))
        #expect(!prompt.contains("Avg sessions/week"))
    }

    /// The prompt used to label the recent window `Current segment (last 4–8 weeks):`, and
    /// the model presented that label to the reader as a period: *"in den letzten 4–8
    /// Wochen"*. The window is the app's bucketing parameter, not a fact about the
    /// reader's training, so it no longer appears in the prompt at all.
    @Test("The recent segment's label carries no window for the model to quote")
    func recentSegmentLabelNamesNoWindow() {
        let prompt = makeInput().toPromptText(in: .kilograms)

        #expect(prompt.contains("Recent segment:"))
        #expect(!prompt.contains("4–8"))
        #expect(!prompt.contains("last 4"))
    }

    /// The fabricated `87,5 kg → 88,2 kg` had two causes, and the removed instruction
    /// literal was only the second. The first was a demand: the prompt labelled the block
    /// `Overall progression (first → most recent session):` and the guide asked for "how
    /// the estimated 1RM changed from the first session to the most recent" — naming two
    /// endpoints the input has never carried. Asked for an endpoint, the model supplied
    /// one. Never describe a shape that presupposes data the prompt does not hold.
    @Test("The progression block offers a change, and never implies an endpoint value")
    func progressionOffersNoEndpointToName() {
        let prompt = makeInput().toPromptText(in: .kilograms)

        #expect(prompt.contains("no starting or ending 1RM value is available"))
        #expect(prompt.contains("Estimated 1RM change:"))
        #expect(!prompt.contains("first → most recent"))
        #expect(!prompt.contains("Estimated 1RM delta"))

        let schema = String(describing: ExerciseDeepDiveOutput.generationSchema)
        #expect(schema.contains("NEVER NAME A FIRST OR MOST-RECENT 1RM FIGURE"))
    }

    // MARK: - The pre-resolved peak sentence

    @Test("The peak sentence carries the peak's own figures, in the reader's convention")
    func peakSentenceIsComposedInSwift() {
        let german = makeInput(locale: "de_DE").peakSentence(in: .kilograms)
        #expect(german.contains("20,0"))
        #expect(german.contains("24,0"))
        #expect(german.contains("August 2026"))
        // The template resolved — an unresolved key would come back as the key itself.
        #expect(!german.contains("ai_coach.deep_dive.peak"))

        let english = makeInput(locale: "en_US").peakSentence(in: .kilograms)
        #expect(english.contains("20.0"))
        #expect(english.contains("24.0"))
    }

    // MARK: - Field guides and prompts carry the rules the lists did not

    /// Three field-level rules, each added after the prompt-level copy of it was ignored
    /// on a device check: a bare date range answered `workload`, `progression` was skipped
    /// on a single-variant view, and `closing` produced prescriptive training advice.
    @Test("Each field's guide carries the rule its own device failure needs")
    func fieldGuidesCarryTheirOwnConstraints() {
        let schema = String(describing: ExerciseDeepDiveOutput.generationSchema)

        #expect(schema.contains("a bare date range or a fragment is not an answer"))
        #expect(schema.contains("Required whenever the input contains an 'Overall progression' block"))
        #expect(schema.contains("NEVER TELL THE READER WHAT TO DO"))
    }

    /// The prescriptive-advice rule was in both prompts and was ignored anyway — it now
    /// names the exact evasion the model used ("a good indicator that you should…").
    @Test("Both prompts forbid prescriptive advice in all-caps")
    func bothPromptsForbidPrescriptiveAdvice() {
        for prompt in [
            ExerciseDeepDiveInstructions.singleVariantPrompt,
            ExerciseDeepDiveInstructions.blendedViewPrompt
        ] {
            #expect(prompt.contains("NEVER TELL THE READER WHAT TO DO"))
            #expect(prompt.contains("training frequency"))
        }
    }

    // The single worst failure this surface has produced — the model lifting `87.5 kg`
    // out of the instructions' own worked example and presenting it as the reader's data
    // — is now pinned for **every** coach surface at once, in
    // `CoachPromptGroundingTests.noCoachPromptCarriesADataShapedLiteral`. Both deep-dive
    // prompts are in that scan; the rule is one rule and is stated once.

    /// The whole app addresses the reader informally; the model wrote formal German
    /// throughout ("Sie haben insgesamt 6 Trainingseinheiten analysiert", "Ihre
    /// Trainingsfrequenz"). Naming "du" as the preferred form was not enough — the formal
    /// register had to be forbidden by name.
    @Test("Both prompts forbid the formal German register by name")
    func bothPromptsForbidTheFormalRegister() {
        for prompt in [
            ExerciseDeepDiveInstructions.singleVariantPrompt,
            ExerciseDeepDiveInstructions.blendedViewPrompt
        ] {
            #expect(prompt.contains("informal throughout: du, dein, dir, dich"))
            #expect(prompt.contains("NEVER use the formal Sie"))
            // Adjacent to the prepended language directive, not buried in the rule list.
            #expect(prompt.hasPrefix("When you write German it is informal"))
        }
    }

    // MARK: - The output's shape, and what the app does with it

    /// The shape lives in the type: one field per paragraph. A blended view has no
    /// progression paragraph, and the app drops one whatever the model returned — the
    /// half of the guarantee that does not depend on the model obeying its instructions.
    @Test("A blended narrative drops the progression paragraph the model returned anyway")
    func blendedNarrativeNeverStatesAProgression() {
        let output = ExerciseDeepDiveOutput(
            workload: "21 Sitzungen zwischen Juli 2026 und August 2026.",
            progression: "Dein geschätztes 1RM ist um 1,5 kg gestiegen.",
            closing: "Eine Progression braucht eine einzelne Variante."
        )

        let blended = ExerciseDeepDiveNarrative(
            output: output,
            peakSentence: "Bestwert: 20,0 kg × 6 Wdh.",
            statesProgression: false
        )
        #expect(blended.progression == nil)
        #expect(blended.workload == output.workload)
        #expect(blended.closing == output.closing)

        let single = ExerciseDeepDiveNarrative(
            output: output,
            peakSentence: "Bestwert: 20,0 kg × 6 Wdh.",
            statesProgression: true
        )
        #expect(single.progression == output.progression)
    }

}
