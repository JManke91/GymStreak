//
//  ExerciseNameResolverTests.swift
//  GymStreakTests
//
//  Validates the chat exercise-name resolution the spike iterated on: folded
//  exact/contains/token matching, German umlaut equivalence, same-name
//  aggregation, genuine ambiguity, and total misses. Pure logic — no model.
//

import Testing
import SwiftData
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseNameResolverTests {

    private let resolver = ExerciseNameResolver()

    private func library(_ names: [String]) -> [Exercise] {
        let context = ModelContext(InMemoryModelContainer.make())
        return names.map { name in
            let exercise = Exercise(name: name)
            context.insert(exercise)
            return exercise
        }
    }

    @Test func exactMatchResolvesUniquely() {
        guard case .resolved(let hits) = resolver.resolve("Bench Press", in: library(["Bench Press", "Squat"])) else {
            Issue.record("expected .resolved"); return
        }
        #expect(hits.count == 1)
        #expect(hits.first?.name == "Bench Press")
    }

    @Test func foldsGermanUmlautAndCase() {
        let lib = library(["Bankdrücken"])
        // "ue" digraph form and all-caps both fold to the stored "Bankdrücken".
        guard case .resolved(let a) = resolver.resolve("bankdruecken", in: lib) else {
            Issue.record("ue form should resolve"); return
        }
        #expect(a.first?.name == "Bankdrücken")
        guard case .resolved = resolver.resolve("BANKDRÜCKEN", in: lib) else {
            Issue.record("uppercase umlaut should resolve"); return
        }
    }

    @Test func sameNameEntriesAggregate() {
        // Two library entries with an identical name (e.g. barbell + dumbbell).
        guard case .resolved(let hits) = resolver.resolve("biceps curls", in: library(["Biceps Curls", "Biceps Curls"])) else {
            Issue.record("expected .resolved aggregating both"); return
        }
        #expect(hits.count == 2)
    }

    @Test func distinctNamesAreAmbiguous() {
        guard case .ambiguous(let names) = resolver.resolve("Curls", in: library(["Biceps Curls", "Biceps Curls Maschine"])) else {
            Issue.record("expected .ambiguous"); return
        }
        #expect(names.contains("Biceps Curls"))
        #expect(names.contains("Biceps Curls Maschine"))
    }

    @Test func tokenOverlapResolvesNickname() {
        guard case .resolved(let hits) = resolver.resolve("bench", in: library(["Bench Press", "Squat"])) else {
            Issue.record("expected .resolved"); return
        }
        #expect(hits.first?.name == "Bench Press")
    }

    // MARK: - German compounds (device regression, 2026-09-16)

    /// A qualifier compounded onto the front of a stored name makes a **different**
    /// exercise, and step 2 used to throw it away: `fold("Schrägbankdrücken")` contains
    /// `"bankdruecken"`, so a library "Bankdrücken" came back as the single, confident
    /// `.resolved` answer — not `.ambiguous`, not `.noMatch`.
    ///
    /// It reached a device through the routine draft, which wrote *Bankdrücken 3 × 10 @
    /// 22 kg* into a routine whose author had asked for incline pressing, and displayed it
    /// as if it were right. The same rule had Coach Chat answer a Schrägbankdrücken PR
    /// question with the Bankdrücken numbers.
    ///
    /// `.noMatch` is the correct answer here: the chat then hands the model the library so
    /// it can map the name, and the routine draft leaves the exercise out and says so.
    @Test func compoundPrefixDoesNotResolveToTheStemExercise() {
        let lib = library(["Bankdrücken", "Kniebeugen"])

        guard case .noMatch = resolver.resolve("Schrägbankdrücken", in: lib) else {
            Issue.record("a compound prefix must not resolve to the stem exercise"); return
        }
        guard case .noMatch = resolver.resolve("Frontkniebeugen", in: lib) else {
            Issue.record("Frontkniebeugen is not Kniebeugen"); return
        }
    }

    /// The other half of the same rule: when the library *does* carry the compound, the
    /// query still resolves — the fix removes a wrong match, not a right one.
    @Test func compoundResolvesWhenTheLibraryCarriesIt() {
        let lib = library(["Bankdrücken (Langhantel)", "Schrägbankdrücken (Kurzhantel)"])

        guard case .resolved(let hits) = resolver.resolve("Schrägbankdrücken", in: lib) else {
            Issue.record("expected .resolved against the compound entry"); return
        }
        #expect(hits.first?.name == "Schrägbankdrücken (Kurzhantel)")

        // And the stem still finds its own entry rather than the compound one.
        guard case .resolved(let stem) = resolver.resolve("Bankdrücken", in: lib) else {
            Issue.record("expected .resolved for the stem"); return
        }
        #expect(stem.first?.name == "Bankdrücken (Langhantel)")
    }

    /// Both compound variants present is genuine ambiguity, and stays a question rather
    /// than becoming a guess.
    @Test func twoCompoundVariantsStayAmbiguous() {
        let lib = library(["Schrägbankdrücken (Langhantel)", "Schrägbankdrücken (Kurzhantel)"])

        guard case .ambiguous(let names) = resolver.resolve("Schrägbankdrücken", in: lib) else {
            Issue.record("expected .ambiguous across the two variants"); return
        }
        #expect(names.count == 2)
    }

    /// A qualifier that stands as its **own word** is a qualified mention, not a different
    /// word, and still resolves. This is long-standing behaviour the boundary rule
    /// deliberately leaves alone — pinned so the distinction is not lost by accident.
    @Test func aSeparateQualifierWordStillResolves() {
        guard case .resolved(let hits) = resolver.resolve("Enges Bankdrücken", in: library(["Bankdrücken"])) else {
            Issue.record("a separate qualifier word still resolves"); return
        }
        #expect(hits.first?.name == "Bankdrücken")
    }

    @Test func unknownNameIsNoMatch() {
        guard case .noMatch = resolver.resolve("Kreuzheben", in: library(["Bench Press", "Squat"])) else {
            Issue.record("expected .noMatch"); return
        }
    }

    @Test func emptyLibraryIsNoMatch() {
        guard case .noMatch = resolver.resolve("anything", in: library([])) else {
            Issue.record("expected .noMatch"); return
        }
    }
}
