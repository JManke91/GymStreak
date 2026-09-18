//
//  RoutineDraftRows.swift
//  GymStreak
//
//  How a grounded routine draft reads on screen: one finished value struct per drafted
//  exercise, composed once per change rather than per render.
//  See docs/ai-coach-routine-drafting.md.
//

import Foundation

/// One row of the drafting sheet's review list: a value struct, never a
/// `GroundedDraftExercise`.
///
/// A resolved row's `name` is the **library exercise's own name**, not the model's
/// spelling of it; an unresolved row's is what the person actually said, because that is
/// the only thing they can recognise it by. `summary` is a finished string. A row view
/// that held the drafted exercise would read an `@Model` property — and format a weight —
/// once per row per render (CLAUDE.md § "Performance: main thread and rendering",
/// rules 2 and 4).
struct RoutineDraftRow: Identifiable, Equatable, Hashable {

    let id: UUID
    let name: String
    let summary: String
    /// Why this row still needs the person — several library exercises match, or none
    /// does — or `nil` once it names a real library exercise.
    let hint: String?

    /// A resolved row is one with nothing left to ask. Everything the sheet offers on an
    /// unresolved row (the picker, the remove button) is keyed off this.
    var isResolved: Bool { hint == nil }
}

/// Turns a grounded draft into the review list.
///
/// Its own type rather than a method on the ViewModel because it is the one place a
/// weight gets formatted and a localized string gets chosen for this surface, and because
/// that makes the mapping assertable without a ViewModel, a gate or a stream.
struct RoutineDraftRowComposer {

    /// The reader's display unit — the drafted weights are canonical kilograms and are
    /// formatted back into it exactly once, here.
    let weightUnit: WeightUnit

    func rows(for draft: GroundedRoutineDraft) -> [RoutineDraftRow] {
        draft.exercises.map { drafted in
            RoutineDraftRow(
                id: drafted.id,
                name: drafted.exercise?.name ?? drafted.draftedName,
                summary: summary(for: drafted),
                hint: hint(for: drafted.match)
            )
        }
    }

    /// The row's finished subtitle, built here so no row view formats a weight. It is
    /// composed for an unresolved row too: the figures the description gave survive
    /// resolution, and showing them is what says so.
    ///
    /// A drafted exercise with no load reads as sets and reps alone, which is what a
    /// bodyweight movement should say.
    private func summary(for drafted: GroundedDraftExercise) -> String {
        var parts = [
            "routine.sets_count".localized(drafted.setCount),
            "set.reps".localized(drafted.reps),
        ]
        if drafted.weightKilograms > 0 {
            parts.append(WeightFormatting.label(drafted.weightKilograms, in: weightUnit))
        }
        return parts.joined(separator: " • ")
    }

    /// What an unresolved row says about itself, or `nil` when it is resolved.
    ///
    /// The two failing cases stay apart all the way to the screen: "several match" is a
    /// promise the picker keeps by offering those few first, and saying it where the
    /// answer is really the whole library would be a lie.
    private func hint(for match: GroundedDraftExercise.Match) -> String? {
        switch match {
        case .resolved: nil
        case .ambiguous: "ai_coach.routine_draft.unresolved.ambiguous".localized
        case .unmatched: "ai_coach.routine_draft.unresolved.not_in_library".localized
        }
    }
}
