//
//  RoutineDraftFiguresTests.swift
//  GymStreakTests
//
//  `RoutineDraftFigures` (docs/ai-coach-routine-drafting.md §4a): reading the rest times,
//  rep ranges and loads a person typed, so a drafted figure the model misplaced or made up
//  never reaches the store — and typed text, being a system boundary, never traps.
//

import Foundation
import Testing
@testable import GymStreak

struct RoutineDraftFiguresTests {

    @Test("A load the person never wrote is no load; one they wrote is kept, even beside the same rest figure")
    func loadMustBeTyped() {
        let invented = RoutineDraftFigures(words: "Push: Bankdrücken 3 Sätze à 8, 2 Minuten Pause")
        #expect(!invented.isStatedLoad(20, setCount: 3, reps: 8))
        #expect(!invented.isStatedLoad(8, setCount: 3, reps: 8))

        let sameFigure = RoutineDraftFigures(words: "Bankdrücken 3x8 mit 60 kg, 60 Sekunden Pause")
        #expect(sameFigure.isStatedLoad(60, setCount: 3, reps: 8))
        #expect(sameFigure.restTimes == [60])

        let bare = RoutineDraftFigures(words: "bench press 3x8 at 62,5")
        #expect(bare.isStatedLoad(62.5, setCount: 3, reps: 8))
        #expect(RoutineDraftFigures(words: "135lbs").isStatedLoad(135, setCount: 3, reps: 8))
    }

    @Test("A huge typed number is read without trapping, and is no range")
    func hugeTypedNumberDoesNotCrash() {
        let figures = RoutineDraftFigures(words: "bench 100000000000000000000-5, 99999999999999999999999 bis 12, 7.5-10")
        #expect(!figures.isStatedRange(low: 7, high: 10))
        #expect(!figures.isStatedRange(low: 5, high: 12))
    }

    @Test("A count from another exercise is not a load")
    func countsAreNotLoads() {
        let figures = RoutineDraftFigures(words: "Bankdrücken 3x8-12, Kniebeugen 5x5 100kg")
        #expect(!figures.isStatedLoad(12, setCount: 3, reps: 8))
        #expect(!figures.isStatedLoad(5, setCount: 3, reps: 8))
        #expect(figures.isStatedLoad(100, setCount: 5, reps: 5))
        #expect(!RoutineDraftFigures(words: "Dips 4 Sätze 10 Wdh.").isStatedLoad(10, setCount: 4, reps: 12))
        // "à 8" / "sets of 8" is a rep count, even when the model hands it to another exercise.
        let aCount = RoutineDraftFigures(words: "Bankdrücken 3 Sätze à 8, Kniebeugen 3 Sätze à 5 mit 100kg")
        #expect(!aCount.isStatedLoad(8, setCount: 3, reps: 5))
        #expect(!RoutineDraftFigures(words: "bench 3 sets of 8, squat 5x5").isStatedLoad(8, setCount: 5, reps: 5))
    }

    @Test("A distance or a time of day is not a rest")
    func distanceAndTimeOfDayAreNotRest() {
        #expect(RoutineDraftFigures(words: "Farmer's Walk 4x40 m").restTimes.isEmpty)
        #expect(RoutineDraftFigures(words: "Training um 18:30, Bankdrücken 3x8").restTimes.isEmpty)
        // A lone time-shaped figure without the word "Pause"/"rest" is not taken on the
        // model's say-so.
        let noRestWord = RoutineDraftFigures(words: "Plank 3x 45 s")
        #expect(noRestWord.statedRest(drafted: 600, draftedAmount: 10) == nil)
        #expect(noRestWord.statedRest(drafted: 45, draftedAmount: 45) == 45)
    }

    @Test("A figure word is never an exercise name")
    func figureWordsAreNotExercises() {
        for name in ["Pause", "Sätze", "90 Sekunden Pause", "kg", "Wiederholungsziel", "rest"] {
            #expect(RoutineDraftFigures.isFigureVocabulary(name), "\(name)")
        }
        for name in ["Bankdrücken", "Rest-Pause Bench", "Farmer's Walk"] {
            #expect(!RoutineDraftFigures.isFigureVocabulary(name), "\(name)")
        }
    }

    @Test("Each exercise gets its own stretch of the words; a skipped name is ignored")
    func segmentsSplitTheWordsByName() {
        let segments = RoutineDraftFigures.segments(
            for: ["Bankdrücken", "Kniebeugen", ""],
            in: "Push: Bankdrücken 3x8 mit 60 kg, Kniebeugen 5x5 mit 100 kg, 2 Minuten Pause"
        )
        #expect(segments[0] == "bankdrücken 3x8 mit 60 kg, ")
        #expect(segments[1] == "kniebeugen 5x5 mit 100 kg, 2 minuten pause")
        #expect(segments[2] == nil)
        #expect(segments[0].map { RoutineDraftFigures(words: $0).onlyUnitLoad } == 60)
    }

    /// The three inputs the architecture review (2026-09-27) showed moving a figure to
    /// another exercise. Each must leave the segmentation untrusted — no segment at all.
    @Test("Segmentation that could move a figure to another exercise is not trusted",
          arguments: [
            // An inflected neighbour cannot be located, so Klimmzüge would span the squat.
            (["Klimmzüge", "Kniebeugen", "Dips"], "Klimmzüge 3x8, Kniebeuge 5x5 100kg 8-12, Dips 3x10"),
            // Figures before their names: each segment would hold the next one's load.
            (["Kniebeugen", "Bankdrücken"], "100kg Kniebeugen 5x5, 60kg Bankdrücken 3x8"),
            // A follow-up answer repeats the names.
            (["Kniebeugen", "Bankdrücken"], "Kniebeugen und Bankdrücken\nKniebeugen 5x5 100kg, Bankdrücken 3x8"),
            // A name inside a longer one is not "exactly once".
            (["Bankdrücken", "Schrägbankdrücken"], "Bankdrücken 3x8 60kg, Schrägbankdrücken 3x10 22kg"),
          ])
    func untrustedSegmentation(names: [String], words: String) {
        #expect(RoutineDraftFigures.segments(for: names, in: words).allSatisfy { $0 == nil })
    }

    @Test("A segment ends at the end of its line")
    func segmentEndsAtLineBreak() {
        let segments = RoutineDraftFigures.segments(for: ["Bankdrücken"], in: "Bankdrücken 3x8\n60kg")
        #expect(segments == ["bankdrücken 3x8"])
    }

    @Test("A load or rest span is not a rep range")
    func unitSpansAreNotRanges() {
        let figures = RoutineDraftFigures(words: "Bankdrücken 3x8 mit 60-80 kg, 60-90 Sekunden Pause")
        #expect(figures.onlyRange == nil)
        #expect(RoutineDraftFigures(words: "Bankdrücken 3x8-12 mit 60kg").onlyRange.map { [$0.low, $0.high] } == [8, 12])
    }

    @Test("A count is stated only when the person wrote that number, in digits or as a word")
    func countsMustBeTyped() {
        #expect(!RoutineDraftFigures(words: "Bankdrücken und Kniebeugen").isStatedCount(3))
        #expect(RoutineDraftFigures(words: "Bankdrücken 3x8-12").isStatedCount(3))
        #expect(RoutineDraftFigures(words: "Bankdrücken 3x8-12").isStatedCount(12))
        #expect(RoutineDraftFigures(words: "je vier").isStatedCount(4))
        #expect(RoutineDraftFigures(words: "four each").isStatedCount(4))
        // An article is not a count.
        #expect(!RoutineDraftFigures(words: "eine Push-Routine").isStatedCount(1))
    }
}
