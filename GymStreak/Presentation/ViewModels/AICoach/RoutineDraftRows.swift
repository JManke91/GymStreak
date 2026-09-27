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
    /// The rep-range goal and rest time, e.g. "No rep goal • Rest 1m". "No rep goal" is
    /// spelled out rather than left blank: it is the usual, legitimate state of a drafted
    /// exercise, and a blank would read as something that failed to load.
    var goals: String = ""
    /// Why this row still needs the person — several library exercises match, or none
    /// does — or `nil` once it names a real library exercise.
    let hint: String?
    /// Whether the row has a neighbour above / below to swap with. Composed here so the
    /// row's move menu disables the impossible direction without knowing the list.
    let canMoveUp: Bool
    let canMoveDown: Bool

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

    /// - Parameter edits: rows the person reopened in `ConfigureExerciseSetsView`, keyed
    ///   by drafted-row id. An edited row's summary describes what that screen returned —
    ///   per-set reps and weights may now differ — rather than the drafted scheme.
    /// - Parameter showsDefaults: `false` while the sheet is still asking questions, so an
    ///   unstated set count reads as the open question it is rather than as the Swift
    ///   default it will fall back to at review.
    func rows(
        for draft: GroundedRoutineDraft,
        edits: [UUID: PendingRoutineExercise] = [:],
        showsDefaults: Bool = true
    ) -> [RoutineDraftRow] {
        let lastIndex = draft.exercises.count - 1
        return draft.exercises.enumerated().map { index, drafted in
            RoutineDraftRow(
                id: drafted.id,
                name: drafted.exercise?.name ?? drafted.draftedName,
                summary: edits[drafted.id]?.setSummary(in: weightUnit) ?? summary(for: drafted, showsDefaults: showsDefaults),
                goals: edits[drafted.id].map {
                    goals(repMin: $0.targetRepMin, repMax: $0.targetRepMax, restTime: $0.sets.first?.restTime ?? 0)
                } ?? goals(repMin: drafted.targetRepMin, repMax: drafted.targetRepMax, restTime: drafted.restTime),
                hint: hint(for: drafted.match),
                canMoveUp: index > 0,
                canMoveDown: index < lastIndex
            )
        }
    }

    /// The row's finished subtitle, built here so no row view formats a weight. It is
    /// composed for an unresolved row too: the figures the description gave survive
    /// resolution, and showing them is what says so.
    ///
    /// A drafted exercise with no load reads as sets and reps alone, which is what a
    /// bodyweight movement should say.
    private func summary(for drafted: GroundedDraftExercise, showsDefaults: Bool) -> String {
        var parts = [
            drafted.isSetCountStated || showsDefaults
                ? "routine.sets_count".localized(drafted.setCount)
                : "ai_coach.routine_draft.sets_unstated".localized,
            "set.reps".localized(drafted.reps),
        ]
        if drafted.weightKilograms > 0 {
            parts.append(WeightFormatting.label(drafted.weightKilograms, in: weightUnit))
        }
        return parts.joined(separator: " • ")
    }

    /// The row's goal line. An edited row reads from what the set editor returned, whose
    /// rest can be switched off entirely.
    private func goals(repMin: Int?, repMax: Int?, restTime: TimeInterval) -> String {
        let goal = if let repMin, let repMax {
            "ai_coach.routine_draft.rep_goal".localized(repMin, repMax)
        } else {
            "ai_coach.routine_draft.no_rep_goal".localized
        }
        let rest = restTime > 0
            ? "ai_coach.routine_draft.rest".localized(TimeFormatting.formatRestTime(restTime))
            : "ai_coach.routine_draft.rest_off".localized
        return [goal, rest].joined(separator: " • ")
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

/// What the "routine created" confirmation shows: the name that was written, a finished
/// totals line, and the exercises as the review list last showed them, already numbered.
/// A value struct built once in `createRoutine()`, so the success view formats, counts and
/// enumerates nothing.
struct CreatedRoutineSummary: Equatable {

    struct Entry: Identifiable, Equatable {
        let id: UUID
        /// 1-based position in the saved routine.
        let number: Int
        let name: String
        let summary: String
        let isLast: Bool
    }

    let name: String
    /// e.g. "3 exercises • 10 sets".
    let totals: String
    let exercises: [Entry]

    init(name: String, exerciseCount: Int, setCount: Int, rows: [RoutineDraftRow]) {
        self.name = name
        exercises = rows.enumerated().map { index, row in
            Entry(
                id: row.id,
                number: index + 1,
                name: row.name,
                summary: row.summary,
                isLast: index == rows.count - 1
            )
        }
        // No stringsdict in this app, so the singular is its own key.
        let exerciseText = exerciseCount == 1
            ? "ai_coach.routine_draft.created.exercises.one".localized
            : "ai_coach.routine_draft.created.exercises.other".localized(exerciseCount)
        let setText = setCount == 1
            ? "ai_coach.routine_draft.created.sets.one".localized
            : "routine.sets_count".localized(setCount)
        totals = [exerciseText, setText].joined(separator: " • ")
    }
}
