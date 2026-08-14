//
//  ExerciseNameResolver.swift
//  GymStreak
//
//  Resolves a free-form, user-typed exercise name (in any language) to the live
//  Exercise library. See docs/ai-coach-chat-feasibility.md (Device-test findings)
//  for why cross-language names need the model-assisted fallback.
//
//  Pure logic over already-fetched `Exercise` models, so it lives in `Domain/`
//  and stays isolation-agnostic: audit P1.3 moved its caller into a model actor,
//  which calls this from its own executor (docs/swift6-concurrency.md §10 rule 3).
//  It was `@MainActor` while it lived in `Data/AICoach/Chat/`; that annotation was
//  incidental to the old main-actor fact service, not a requirement.
//

import Foundation

struct ExerciseNameResolver {

    enum Match {
        /// One or more exercises that resolve to the SAME name. Multiple means the
        /// user has several library entries with an identical name (e.g. a barbell
        /// and a dumbbell "Biceps Curls") — they are indistinguishable by name
        /// (the tool re-call is keyed on name), so we aggregate them as one rather
        /// than pose an unanswerable "which one?".
        case resolved([Exercise])
        /// Distinct names matched — the model asks the user which they mean.
        case ambiguous([String])
        /// No lexical match. The caller hands the full library to the model to
        /// map semantically / across languages — pure string matching cannot.
        case noMatch
    }

    /// Exact → contains → token-overlap match against the library, both
    /// directions, over a folded form (diacritics/umlauts normalized — see
    /// `fold`). Distinct-name matches return `.ambiguous`; same-name matches
    /// aggregate into `.resolved`; a total miss returns `.noMatch`. A dynamic
    /// `.anyOf` over all names was rejected (token cost + fuzzy phrasing) — see docs.
    func resolve(_ query: String, in library: [Exercise]) -> Match {
        let normalized = fold(query)
        guard !normalized.isEmpty, !library.isEmpty else { return .noMatch }

        // 1. Exact (folded) — same-name duplicates aggregate into one target.
        let exact = library.filter { fold($0.name) == normalized }
        if !exact.isEmpty { return .resolved(exact) }

        // 2. Substring either direction (folded).
        let contains = library.filter {
            let name = fold($0.name)
            return name.contains(normalized) || normalized.contains(name)
        }
        if let match = disambiguate(contains) { return match }

        // 3. Token overlap (folded).
        let queryTokens = Set(tokens(normalized))
        guard !queryTokens.isEmpty else { return .noMatch }
        let scored = library
            .map { (exercise: $0, overlap: Set(tokens(fold($0.name))).intersection(queryTokens).count) }
            .filter { $0.overlap > 0 }
            .sorted { $0.overlap > $1.overlap }

        guard let topOverlap = scored.first?.overlap else { return .noMatch }
        let best = scored.filter { $0.overlap == topOverlap }.map(\.exercise)
        return disambiguate(best) ?? .noMatch
    }

    /// Collapses candidates into a single `.resolved` when they all share one
    /// folded name (aggregate); returns `.ambiguous` when the names differ so the
    /// model can ask. `nil` for an empty candidate set.
    private func disambiguate(_ candidates: [Exercise]) -> Match? {
        guard !candidates.isEmpty else { return nil }
        let distinctNames = Set(candidates.map { fold($0.name) })
        if distinctNames.count == 1 { return .resolved(candidates) }
        return .ambiguous(dedupedNames(candidates))
    }

    /// Whether a history `WorkoutExercise` refers to `exercise` — by id when
    /// tagged, else by folded-name match (legacy untagged rows).
    func matches(_ workoutExercise: WorkoutExercise, _ exercise: Exercise) -> Bool {
        if let id = workoutExercise.exerciseId { return id == exercise.id }
        return fold(workoutExercise.exerciseName) == fold(exercise.name)
    }

    /// Sorted, de-duplicated library names — the list handed to the model on a
    /// `.noMatch` so it can map the query across languages.
    func sortedUniqueNames(_ library: [Exercise]) -> [String] {
        dedupedNames(library.sorted { $0.name < $1.name })
    }

    // MARK: - Private

    /// Normalizes a string for lexical comparison: expands German umlauts/ß to
    /// their digraph form so "Bankdrücken" and "Bankdruecken" unify, folds other
    /// diacritics, lowercases, and trims. Bridges same-language spelling variants
    /// only — cross-language equivalents are the model's job.
    private func fold(_ text: String) -> String {
        let digraphs: [Character: String] = [
            "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
            "Ä": "ae", "Ö": "oe", "Ü": "ue",
        ]
        let expanded = String(text.flatMap { digraphs[$0].map(Array.init) ?? [$0] })
        return expanded
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokens(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private func dedupedNames(_ exercises: [Exercise]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for exercise in exercises where seen.insert(exercise.name.lowercased()).inserted {
            result.append(exercise.name)
        }
        return result
    }
}
