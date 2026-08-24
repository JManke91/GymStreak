//
//  ExerciseUsageResolver.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Resolves history rows to the **usage** they belong to: which routine slot a set of
/// work was recorded against, which usages an exercise's history contains, and which one
/// a screen ends up showing.
///
/// This is *the* definition of "the same piece of work" in the app. Both surfaces that
/// need it call in here — `ExerciseProgressAggregator` to segment the chart and the
/// recent-sets list, `PreviousPerformanceResolver` for the exact match behind "what did I
/// lift last time?". Two implementations would let the save sheet and the chart drift
/// apart about which sets belong together, which is precisely how the two panels of the
/// exercise detail screen came to contradict each other in the first place.
///
/// Pure and isolation-agnostic. **Never add `@MainActor`** (`docs/swift6-concurrency.md`
/// §10 rule 3): the model actor calls it from its own executor.
enum ExerciseUsageResolver {

    /// The routine slot a history row belongs to.
    ///
    /// A row with no `routineExerciseId` — history recorded before the field existed, and
    /// exercises added ad hoc mid-workout — resolves to the explicit `.unattributed`
    /// bucket rather than to `nil` or to some other usage.
    static func slot(of exercise: WorkoutExercise) -> ExerciseUsage.Slot {
        exercise.routineExerciseId.map(ExerciseUsage.Slot.routineSlot) ?? .unattributed
    }

    /// One workout's matching rows, each tagged with the usage key it belongs to, in the
    /// order the user performed them.
    ///
    /// The single place the occurrence index is assigned, so the chart, the recent-sets
    /// list and the picker can never disagree about which row is which usage. A routine
    /// slot is not unique inside a workout in real history (see `ExerciseUsage.Key`), and
    /// the index is what keeps two rows of one slot from collapsing into a single series.
    ///
    /// **Ordering is explicit, never inherited.** `workoutExercisesList` is the raw
    /// SwiftData to-many array, whose order is undocumented, so rows are sorted by
    /// `WorkoutExercise.order` — the sequence actually performed — with `id` as a
    /// tiebreak, making it a total order even when two rows share an `order`.
    static func keyedRows(
        in session: WorkoutSession,
        matching isMatch: (WorkoutExercise) -> Bool
    ) -> [(exercise: WorkoutExercise, key: ExerciseUsage.Key)] {
        let ordered = session.workoutExercisesList
            .filter(isMatch)
            .sorted { $0.order != $1.order ? $0.order < $1.order : $0.id.uuidString < $1.id.uuidString }

        var occurrences: [ExerciseUsage.Slot: Int] = [:]
        return ordered.map { exercise in
            let slot = slot(of: exercise)
            let occurrence = occurrences[slot, default: 0]
            occurrences[slot] = occurrence + 1
            return (exercise, ExerciseUsage.Key(slot: slot, occurrence: occurrence))
        }
    }

    /// The usage one history row belongs to: its key, described by the rep-range goal the
    /// row denormalized and the workout's routine name.
    ///
    /// - Parameter occurrence: the row's index among its slot's own rows in this session,
    ///   as assigned by `keyedRows(in:matching:)`. Defaults to 0, which is what every row
    ///   of normal history — one row per slot per workout — carries.
    static func usage(
        of exercise: WorkoutExercise,
        in session: WorkoutSession,
        occurrence: Int = 0
    ) -> ExerciseUsage {
        ExerciseUsage(
            key: ExerciseUsage.Key(slot: slot(of: exercise), occurrence: occurrence),
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            routineName: session.routineName
        )
    }

    /// Whether a keyed history row belongs to the selected usage. `.combined` admits everything.
    static func belongs(_ key: ExerciseUsage.Key, to selection: ExerciseUsageSelection) -> Bool {
        switch selection {
        case .combined: return true
        case .usage(let selected): return key == selected
        }
    }

    /// Every usage found in the given sessions, newest-trained first.
    ///
    /// - Parameters:
    ///   - sessions: the sessions to scan, in any order — **all completed history**, not
    ///     the chart's window. Ticket 03 scoped the menu to the selected timeframe, and it
    ///     reshuffled on every 1M / 1J / Alle tap; a usage the window has no rows for now
    ///     stays listed and renders the empty-chart state, which one tap on a wider range
    ///     recovers from.
    ///   - liveSlotIds: the ids of every `RoutineExercise` currently held by a routine,
    ///     as fetched inside the model actor. A usage whose slot is absent from this set
    ///     is flagged `isArchived` — the user cannot train it again without editing a
    ///     routine. **Only a flag**: it never removes, reorders or merges a usage, whose
    ///     workouts really happened. `nil` means the caller did not look, and nothing is
    ///     flagged; an empty set means it looked and found no live slots, so every
    ///     routine-slot usage is archived.
    ///   - isMatch: whether a row belongs to the exercise being charted. Passed in rather
    ///     than reconstructed here so this stays one rule away from
    ///     `ExerciseProgressAggregator.matches`, never a second copy of it.
    ///
    /// A usage whose rows carry no completed sets is left out: selecting it would offer the
    /// user an empty chart. A usage is described by its **most recent** row because
    /// `targetRepMin`/`targetRepMax` are denormalized per workout — editing the slot's goal
    /// leaves older rows carrying the old range, and labelling the picker from those would
    /// name a goal the user has since changed. "Most recent" is an explicit
    /// greatest-`(startTime, order, id)` comparison rather than last-write-wins: two
    /// orderings feeding this are undefined (a `sorted(by:)` tie between sessions sharing a
    /// `startTime`, and several rows of one slot inside one session), and taking whichever
    /// row happened to arrive last made the same slot read `4–6 Wdh.` on one load and
    /// `8–12 Wdh.` on the next.
    static func options(
        in sessions: [WorkoutSession],
        liveSlotIds: Set<UUID>? = nil,
        matching isMatch: (WorkoutExercise) -> Bool
    ) -> [ExerciseUsageOption] {
        var best: [ExerciseUsage.Key: (option: ExerciseUsageOption, rank: DescriptorRank)] = [:]

        for session in sessions where session.endTime != nil {
            for row in keyedRows(in: session, matching: isMatch)
            where row.exercise.setsList.contains(where: \.isCompleted) {
                let rank = DescriptorRank(
                    startTime: session.startTime,
                    order: row.exercise.order,
                    id: row.exercise.id
                )
                if let existing = best[row.key], existing.rank > rank { continue }
                best[row.key] = (
                    ExerciseUsageOption(
                        usage: usage(of: row.exercise, in: session, occurrence: row.key.occurrence),
                        lastPerformed: session.startTime,
                        lastPerformedOrder: row.exercise.order,
                        isArchived: isArchived(row.key.slot, liveSlotIds: liveSlotIds)
                    ),
                    rank
                )
            }
        }

        // The key tie-break is what makes this a total order: the values come out of a
        // dictionary, so two usages agreeing on both date and order would otherwise sort
        // differently run to run.
        return best.values.map(\.option).sorted {
            if $0.lastPerformed != $1.lastPerformed { return $0.lastPerformed > $1.lastPerformed }
            if $0.lastPerformedOrder != $1.lastPerformedOrder { return $0.lastPerformedOrder < $1.lastPerformedOrder }
            if $0.key.occurrence != $1.key.occurrence { return $0.key.occurrence < $1.key.occurrence }
            return sortKey($0.key.slot) < sortKey($1.key.slot)
        }
    }

    /// Which usage a screen ends up showing.
    ///
    /// The default is the **most recently trained** usage rather than the combined view:
    /// combined is exactly the alternating sawtooth this feature exists to end, so opening
    /// on it would show the reporter their own bug report. Combined stays one tap away.
    ///
    /// A single usage (or none) resolves to `.combined`, which is then identical to that
    /// usage's own series — the picker has nothing to offer and stays hidden.
    ///
    /// A requested usage is **always kept**. The options are all-time, so anything the user
    /// can have picked is still listed; narrowing the timeframe past it draws the
    /// empty-chart state rather than silently swapping the selection out from under them.
    ///
    /// - Parameter options: as returned by `options(in:matching:)`, newest-trained first.
    static func resolveSelection(
        requested: ExerciseUsageSelection?,
        options: [ExerciseUsageOption]
    ) -> ExerciseUsageSelection {
        guard options.count > 1 else { return .combined }
        // Nothing requested — first open, or straight after an exercise switch.
        guard let requested else { return options.first.map { .usage($0.key) } ?? .combined }
        return requested
    }

    /// Which of two rows describes its usage: the greatest `(startTime, order, id)`.
    private struct DescriptorRank: Comparable {
        let startTime: Date
        let order: Int
        let id: UUID

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Whether a slot exists in no live routine any more.
    ///
    /// `.unattributed` is never archived: it has no slot to look up, so the routine
    /// library can say nothing about it. Sweeping it in would relabel every ad-hoc and
    /// pre-`routineExerciseId` row as a dead routine slot, which it never was.
    private static func isArchived(_ slot: ExerciseUsage.Slot, liveSlotIds: Set<UUID>?) -> Bool {
        guard let liveSlotIds, case .routineSlot(let id) = slot else { return false }
        return !liveSlotIds.contains(id)
    }

    private static func sortKey(_ slot: ExerciseUsage.Slot) -> String {
        switch slot {
        case .routineSlot(let id): return id.uuidString
        case .unattributed: return ""
        }
    }
}
