//
//  CoachPromptGroundingTests.swift
//  GymStreakTests
//
//  One rule, pinned once for every AI Coach surface: **no prompt teaches a rule with a
//  literal that could pass as the reader's own data.**
//
//  It is not a theoretical rule. `ExerciseDeepDiveInstructions` taught its copy-exactly
//  rule with a worked example — "If the input says `87.5 kg`, output `87.5 kg` — not 85,
//  not 87" — and on a device check (German, iPhone, 2026-08-29) the model lifted that
//  literal straight out of the instructions and presented it as the reader's training
//  data: "Der geschätzte 1RM ist von 87,5 kg im ersten Training auf 88,2 kg im letzten
//  Training gestiegen", for a reader whose actual best is 20,0 kg. The 88,2 was the real
//  +0,7 kg delta added to the invented base. Instructions are placed verbatim into the
//  prompt, so an example number is indistinguishable from an input number.
//
//  The control case was `blendedViewPrompt`, which has never carried a data-shaped
//  literal and has never invented a figure. The rule that made it the control now covers
//  every surface, and this file is what keeps it there.
//
//  **A green test proves the prompt is clean, never that the output is.** Whether the
//  model obeys what it is handed is a device check; nothing here can stand in for one.
//

import Foundation
import Testing
@testable import GymStreak

/// Deliberately **not** `@MainActor`: every symbol it touches — the prompt statics, the
/// generation schemas, `CoachCorrelationSanitizer` — is isolation-agnostic.
@Suite
struct CoachPromptGroundingTests {

    // MARK: - Every prompt the coach layer sends

    /// Named so a failure says which surface regressed.
    ///
    /// The three unit-parameterised prompts are built in **both** units: the unit word is
    /// interpolated into rules the model copies, so a literal could be reintroduced on one
    /// branch only.
    private static func allCoachPrompts() -> [(name: String, text: String)] {
        var prompts: [(name: String, text: String)] = [
            ("deep dive · single variant", ExerciseDeepDiveInstructions.singleVariantPrompt),
            ("deep dive · blended", ExerciseDeepDiveInstructions.blendedViewPrompt)
        ]
        for unit in WeightUnit.allCases {
            prompts.append(("post-workout recap · \(unit.rawValue)",
                            PostWorkoutRecapInstructions.systemPrompt(unit: unit)))
            prompts.append(("workout analysis · \(unit.rawValue)",
                            WorkoutAnalysisInstructions.systemPrompt(unit: unit)))
            prompts.append(("period recap · \(unit.rawValue)",
                            PeriodRecapInstructions.systemPrompt(unit: unit)))
            prompts.append(("coach chat · \(unit.rawValue)",
                            chatRulesWithoutAmbientContext(unit: unit)))
        }
        return prompts
    }

    /// The chat instructions minus their `Today is <weekday, d MMMM yyyy>.` line.
    ///
    /// That line is the one place in the coach layer where a date in a *system prompt* is
    /// genuine input rather than an example: it is the ambient fact that makes "next
    /// workout" resolvable as "tomorrow", and it carries a real four-digit year. Stripping
    /// it is what lets the same scan cover the chat rules, which are the part a literal
    /// could leak from.
    private static func chatRulesWithoutAmbientContext(unit: WeightUnit) -> String {
        let full = CoachChatInstructions.build(digest: nil, unit: unit)
        let kept = full
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("- Today is ") }
        #expect(kept.count == full.split(separator: "\n", omittingEmptySubsequences: false).count - 1,
                "The chat prompt's ambient date line changed shape — this filter no longer strips it.")
        return kept.joined(separator: "\n")
    }

    /// Every `@Guide(description:)` the coach layer ships. Apple describes a guide as
    /// "effectively another way of prompting", so a data-shaped literal in one leaks
    /// exactly as a literal in an instruction list does.
    private static func allGenerationSchemas() -> [(name: String, text: String)] {
        [
            ("PeriodRecapOutput", String(describing: PeriodRecapOutput.generationSchema)),
            ("WorkoutAnalysisOutput", String(describing: WorkoutAnalysisOutput.generationSchema)),
            ("ExerciseDeepDiveOutput", String(describing: ExerciseDeepDiveOutput.generationSchema)),
            ("PostWorkoutRecapOutput", String(describing: PostWorkoutRecapOutput.generationSchema))
        ]
    }

    // MARK: - The literal scan

    /// Digits that are not part of an ordinary English word or a field name — the
    /// "2 to 3 sentences" style counts are fine; `87.5 kg`, `20.08.2026` and
    /// `1.3 sessions per week` are not.
    private static func dataShapedLiterals(in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"\d+[.,]\d+|\d{4}"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }

    @Test("No coach prompt teaches a rule with a number, date or frequency that could pass as data")
    func noCoachPromptCarriesADataShapedLiteral() throws {
        for (name, text) in Self.allCoachPrompts() {
            let hits = try Self.dataShapedLiterals(in: text)
            #expect(hits.isEmpty, "\(name) prompt carries data-shaped literals: \(hits)")
        }
    }

    @Test("No output guide teaches a rule with a number, date or frequency that could pass as data")
    func noGenerationSchemaCarriesADataShapedLiteral() throws {
        let schemas = Self.allGenerationSchemas()

        // Positive control first. Every assertion below is an emptiness check, so if
        // `GenerationSchema`'s description ever stopped surfacing `@Guide` descriptions
        // they would all pass while pinning nothing.
        #expect(schemas[0].text.contains("Detected patterns"))

        for (name, text) in schemas {
            let hits = try Self.dataShapedLiterals(in: text)
            #expect(hits.isEmpty, "\(name) guides carry data-shaped literals: \(hits)")
        }
    }

    /// The regex has to actually catch the literals that shipped, or the two tests above
    /// are green for the wrong reason.
    @Test("The scan catches the literals that were measured on device")
    func theScanCatchesTheRealFailures() throws {
        #expect(try !Self.dataShapedLiterals(in: "If the input says `87.5 kg`, output `87.5 kg`").isEmpty)
        #expect(try !Self.dataShapedLiterals(in: "Topsatz 2,5 kg schwerer: jetzt 37,5 kg x 6.").isEmpty)
        #expect(try !Self.dataShapedLiterals(in: "Stärkster Zuwachs: Chest Press +7,0 kg").isEmpty)
        #expect(try !Self.dataShapedLiterals(in: "erreicht am 20.08.2026").isEmpty)
        // …and leaves the harmless style counts alone.
        #expect(try Self.dataShapedLiterals(in: "Output exactly 2 to 3 sentences.").isEmpty)
        #expect(try Self.dataShapedLiterals(in: "fill 1-4 exercise highlights").isEmpty)
    }

    // MARK: - No prompt names a programming construct

    /// `PeriodRecapOutput.correlationHighlight` is optional, and both its guide and the
    /// period-recap prompt used to describe the absent case as *"return nil for this
    /// field"* / *"nil means the UI hides the section"*. On a device check the model
    /// answered that literally: it wrote the four-character string `nil` into the field,
    /// and the Auffälligkeiten card rendered it verbatim (German, 2026-08-30).
    ///
    /// A guide is prompt text, so `nil` inside one is a word to write, not an absence to
    /// produce. Absence is asked for in plain language — "leave this field out entirely".
    @Test("No coach prompt or guide asks the model to produce a language construct")
    func noPromptNamesAProgrammingConstruct() {
        let constructs = ["nil", "null", "NULL", "None"]
        for (name, text) in Self.allCoachPrompts() + Self.allGenerationSchemas() {
            for construct in constructs {
                #expect(!text.contains(construct), "\(name) names the construct '\(construct)'")
            }
        }
    }

    /// The replacement wording, pinned so it is not quietly dropped: the field the model
    /// may omit says so, in words, in both the prompt and its guide.
    @Test("The optional correlation field asks for its absence in plain language")
    func theOptionalFieldAsksForAbsenceInWords() {
        let schema = String(describing: PeriodRecapOutput.generationSchema)
        #expect(schema.contains("OMIT THIS FIELD ENTIRELY"))

        for unit in WeightUnit.allCases {
            let prompt = PeriodRecapInstructions.systemPrompt(unit: unit)
            #expect(prompt.contains("LEAVE THIS FIELD OUT ENTIRELY"))
        }
    }

    // MARK: - No prompt asks for arithmetic

    /// Apple documents the on-device model as "not intended for tasks requiring basic
    /// math", and the fabricated `88,2 kg` was arithmetic: the real `+0,7 kg` delta added
    /// to an invented base. Every coach surface hands the model finished values to
    /// rephrase, and says so.
    @Test("Every narrating prompt tells the model the facts are already resolved")
    func narratingPromptsForbidComputation() {
        for unit in WeightUnit.allCases {
            for (name, prompt) in [
                ("post-workout recap", PostWorkoutRecapInstructions.systemPrompt(unit: unit)),
                ("workout analysis", WorkoutAnalysisInstructions.systemPrompt(unit: unit)),
                ("period recap", PeriodRecapInstructions.systemPrompt(unit: unit))
            ] {
                #expect(prompt.contains("Never compute, combine"), "\(name) does not forbid computation")
            }
        }
        #expect(CoachChatInstructions.build(digest: nil, unit: .kilograms)
            .contains("Never do arithmetic yourself"))
    }

    // MARK: - The figures the model is told to copy

    // Rule 1 tells the model to copy each figure "digit for digit, including its decimal
    // separator", and it obeys — so a prompt figure written in the C locale reached a
    // German reader as `1830.0 kg`. That every narrating surface now writes its figures in
    // the reader's own convention is pinned across all four of them in
    // `CoachPromptFigureLocaleTests`, which needs a `ModelContext` for two of them.

    // MARK: - The guard that does not depend on the model

    /// A prompt rule is a request; this is the guarantee. Whatever the model writes into
    /// the field it was told to leave out, the card does not render a placeholder — the
    /// same check runs on the streamed partial, the final output and the cache read.
    @Test("A placeholder correlation never reaches the card")
    func placeholderCorrelationIsRejected() {
        for placeholder in ["nil", "null", "None", "n/a", "-", "—", "keine", "Nichts.", "  nil  ", ""] {
            #expect(CoachCorrelationSanitizer.sanitized(placeholder) == nil,
                    "'\(placeholder)' survived the guard")
        }
        #expect(CoachCorrelationSanitizer.sanitized(nil) == nil)
    }

    @Test("An apologetic correlation never reaches the card")
    func apologeticCorrelationIsRejected() {
        #expect(CoachCorrelationSanitizer.sanitized("There are no notable correlations in this period.") == nil)
        #expect(CoachCorrelationSanitizer.sanitized("Keine Auffälligkeiten in diesem Zeitraum.") == nil)
    }

    /// The guard matches a placeholder as the *whole* answer, never as a substring — a
    /// real finding that happens to contain one of those words has to survive.
    @Test("A real correlation statement survives the guard")
    func realCorrelationSurvives() {
        let real = "In Wochen mit drei Einheiten sind deine Topsätze im Schnitt schwerer ausgefallen."
        #expect(CoachCorrelationSanitizer.sanitized(real) == real)

        let trimmed = CoachCorrelationSanitizer.sanitized("  \(real)  ")
        #expect(trimmed == real)

        // "none" as a word inside a sentence, not as the answer.
        let noneInside = "Sessions where none of your sets were skipped carried the heaviest top sets."
        #expect(CoachCorrelationSanitizer.sanitized(noneInside) == noneInside)
    }
}
