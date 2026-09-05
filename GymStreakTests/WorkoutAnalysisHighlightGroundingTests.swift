//
//  WorkoutAnalysisHighlightGroundingTests.swift
//  GymStreakTests
//
//  Two device findings from the same German round (2026-08-30), both about the highlight
//  list the model owns:
//
//  * four highlights came back, all for one exercise, three of them restating the same
//    top-set change. The prompt asks for "the 1-4 most notable exercises" and the `@Guide`
//    bounds the count, but neither makes the entries distinct;
//  * a highlight detail used the non-word "Topset" although the instruction list's German
//    glossary mandated "Topsatz" — a glossary line among a dozen other rules was not
//    enough, the same lesson as the paragraph-count rule that moved into a `@Guide`.
//
//  What is pinned here is the Swift-side uniquing (a guarantee) and the wording of the
//  guides (a request). **Whether the model obeys the request is a device check.**
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct WorkoutAnalysisHighlightGroundingTests {

    // MARK: - The guarantee: one highlight per exercise

    @Test("Repeated highlights for one exercise collapse to the first")
    func duplicateHighlightsAreDropped() {
        let content = WorkoutAnalysisContent(narrative: narrative(highlights: [
            ("Arnold Press", .improved, "Topsatz 2 kg schwerer."),
            ("Arnold Press", .improved, "Mehr Gewicht im Topsatz."),
            ("Arnold Press", .unchanged, "Wiederholungen unverändert."),
            ("Dip", .declined, "Topsatz leichter als letzte Einheit.")
        ]))

        #expect(content.highlights.map(\.exerciseName) == ["Arnold Press", "Dip"])
        #expect(content.highlights.first?.detail == "Topsatz 2 kg schwerer.",
                "the first highlight for an exercise is the one kept")
    }

    /// The model's copy of the name is not guaranteed to be byte-identical to the input's.
    @Test("Case and surrounding whitespace do not make a second highlight")
    func duplicateMatchingIgnoresCaseAndWhitespace() {
        let content = WorkoutAnalysisContent(narrative: narrative(highlights: [
            ("Arnold Press", .improved, "a"),
            ("  arnold press ", .improved, "b")
        ]))

        #expect(content.highlights.count == 1)
    }

    /// Mid-stream a highlight exists before its name has finished arriving; folding those
    /// together would collapse the rows the reader is watching fill in.
    @Test("Highlights whose name has not arrived yet are all kept")
    func emptyNamesAreNeverDuplicates() {
        let content = WorkoutAnalysisContent(narrative: narrative(highlights: [
            ("", .improved, ""),
            ("", .improved, "")
        ]))

        #expect(content.highlights.count == 2)
    }

    /// A surviving row keeps the id it had before the filter ran, so dropping a duplicate
    /// does not re-key the rows around it.
    @Test("Dropping a duplicate does not renumber the rows that stay")
    func idsSurviveTheFilter() {
        let content = WorkoutAnalysisContent(narrative: narrative(highlights: [
            ("Arnold Press", .improved, "a"),
            ("Arnold Press", .improved, "b"),
            ("Dip", .declined, "c")
        ]))

        #expect(content.highlights.map(\.id) == [0, 2])
    }

    /// The cache is read by the same init: an analysis written before the uniquing pass
    /// existed still holds its duplicates, and a cache entry is never regenerated just
    /// because its prose is stale.
    @Test("A cached analysis with duplicates is uniqued on read")
    func cachedDuplicatesAreDroppedToo() {
        let cached = narrative(highlights: [
            ("Arnold Press", .improved, "a"),
            ("Arnold Press", .improved, "b")
        ])

        #expect(cached.exerciseHighlights.count == 2, "fixture sanity: the stored narrative has both")
        #expect(WorkoutAnalysisContent(narrative: cached).highlights.count == 1)
        #expect(WorkoutAnalysisContent(narrative: cached).toNarrative().exerciseHighlights.count == 1,
                "re-saving the content must not write the duplicate back")
    }

    /// The uniquer is applied at three boundaries — the cache read, the streamed snapshot
    /// and the cached-narrative mapping — so it is pinned on the Domain type as well, not
    /// only through the display struct.
    @Test("The narrative form of the uniquer keeps one highlight per exercise")
    func narrativeUniquerKeepsTheFirstPerExercise() {
        let uniqued = CoachHighlightUniquer.uniqued(narrative(highlights: [
            ("Arnold Press", .improved, "a"),
            ("ARNOLD PRESS", .declined, "b"),
            ("Dip", .declined, "c")
        ]))

        #expect(uniqued.exerciseHighlights.map(\.exerciseName) == ["Arnold Press", "Dip"])
        #expect(uniqued.headline == "Stärkster Zuwachs", "nothing but the highlight list changes")
        #expect(uniqued.closingObservation == "Solide Einheit.")
    }

    // MARK: - The request: what the guides say

    @Test("The distinctness rule sits on the field that holds the list")
    func highlightListGuideAsksForDistinctExercises() {
        let schema = String(describing: WorkoutAnalysisOutput.generationSchema)
        #expect(schema.contains("ONE HIGHLIGHT PER EXERCISE"))
    }

    @Test("The German glossary sits on the fields that carry German prose")
    func germanTermsAreConstrainedOnTheField() {
        let schema = String(describing: WorkoutAnalysisOutput.generationSchema)
        #expect(schema.contains("Topsatz"))
        #expect(schema.contains("Wiederholungen"))
        #expect(schema.contains("Bestwert"))
    }

    /// Naming a wrong token in an instruction makes it available to copy — and the
    /// instruction that spelled the non-words out is the one the model ignored.
    @Test("No prompt spells out the non-word it is trying to prevent")
    func promptsDoNotNameTheNonWord() {
        for unit in WeightUnit.allCases {
            let prompt = WorkoutAnalysisInstructions.systemPrompt(unit: unit)
            #expect(prompt.contains("Topsatz"), "the correct word is still taught")
            #expect(!prompt.contains("Topset"))
            #expect(!prompt.contains("Bestset"))
        }
        #expect(!String(describing: WorkoutAnalysisOutput.generationSchema).contains("Topset"))
    }

    // MARK: - Fixtures

    private func narrative(
        highlights: [(name: String, trend: WorkoutAnalysisTrend, detail: String)]
    ) -> WorkoutAnalysisNarrative {
        WorkoutAnalysisNarrative(
            headline: "Stärkster Zuwachs",
            exerciseHighlights: highlights.map {
                WorkoutAnalysisHighlight(exerciseName: $0.name, trend: $0.trend, detail: $0.detail)
            },
            closingObservation: "Solide Einheit."
        )
    }
}
