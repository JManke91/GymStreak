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
