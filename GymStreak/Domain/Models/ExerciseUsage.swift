//
//  ExerciseUsage.swift
//  GymStreak
//
//  "Exercise usage" — a distinct way one exercise is trained, identified by the routine
//  slot its history rows were recorded against (2026-08-23). Extracted from
//  ExerciseProgressModels.swift when the usage picker landed: the cluster is
//  self-contained, and that file had grown well past this project's size convention.
//

import Foundation

// Note: String+Localization.swift extension provides .localized property

// MARK: - Exercise Usage

/// Which way an exercise was trained: the routine slot its history rows were
/// recorded against, plus what a user needs to recognise that slot.
///
/// The identity already exists in history — `WorkoutExercise` denormalizes
/// `routineExerciseId` and the slot's rep range precisely so they survive routine
/// edits and deletion — so this persists nothing new. It is a `Sendable` value
/// because it is built inside `SwiftDataHistorySnapshotStore`'s model actor.
struct ExerciseUsage: Hashable, Sendable {
    /// The routine slot behind a block of history.
    enum Slot: Hashable, Sendable {
        case routineSlot(UUID)
        /// No slot at all: history recorded before `WorkoutExercise.routineExerciseId`
        /// existed, and exercises added ad hoc during a workout. An explicit case so
        /// these rows are never folded into an arbitrary real usage and never dropped.
        case unattributed
    }

    /// What identifies one usage: the slot **and** which of that slot's own rows within a
    /// single workout this is.
    ///
    /// The occurrence index exists because a routine slot is *not* unique per workout in
    /// real history. The reporter's data holds one slot carrying two rows of the same
    /// session — 20 kg × 5 and 13 kg × 14, unmistakably two different pieces of work —
    /// which the slot alone folds into one series, where `buildProgress`'s per-session
    /// `max` collapses them straight back into the sawtooth this feature exists to end
    /// (see `docs/progress-charts.md`). For normal history — one row per slot per
    /// workout — the index is always 0 and behaviour is exactly as before.
    ///
    /// The index is the row's position among that slot's rows **ordered by
    /// `WorkoutExercise.order`, with `id` as a total-order tiebreak**, never the order the
    /// to-many relationship happens to materialise. Same rule, and same accepted caveat,
    /// as `PreviousPerformanceResolver.occurrenceIndex`: if the user performs the two
    /// blocks in the opposite order in some workout, that workout's rows swap series.
    /// It is the only ordering information the data carries.
    struct Key: Hashable, Sendable {
        let slot: Slot
        let occurrence: Int

        init(slot: Slot, occurrence: Int = 0) {
            self.slot = slot
            self.occurrence = occurrence
        }

        /// A routine slot's first row in a workout — what every normal history row is.
        static func routineSlot(_ id: UUID) -> Key { Key(slot: .routineSlot(id)) }

        /// The first slot-less row of a workout (legacy history, ad-hoc exercises).
        static let unattributed = Key(slot: .unattributed)
    }

    let key: Key
    let targetRepMin: Int?
    let targetRepMax: Int?
    /// `WorkoutSession.routineName`, denormalized — empty when the workout had no routine.
    let routineName: String

    var slot: Slot { key.slot }

    /// "8–12", or "10" when the goal is a single number. Nil when the slot carries
    /// no rep-range goal. Mirrors `WorkoutExerciseDisplay.repRangeText`, which formats
    /// the same pair for the active-workout screen.
    var repRangeText: String? {
        guard let targetRepMin, let targetRepMax else { return nil }
        return targetRepMin == targetRepMax ? "\(targetRepMin)" : "\(targetRepMin)–\(targetRepMax)"
    }
}

// MARK: - Exercise Usage Labelling

/// One labelled usage: an entry of the exercise detail screen's usage picker, or the
/// usage a Fortschritt row headlines.
///
/// Built off the view's read path — in `ExerciseProgressViewModel` for the picker, in
/// `FortschrittAggregator` for the row — rather than in `body`: the label is a localized
/// string plus a duplicate check across the option array, which the rendering rules keep
/// out of a view's read path. One type and one labeller for both, so a usage is not named
/// one thing in the list and another on the screen that list opens — with one documented
/// exception: the list cannot mark an archived usage, because it does not fetch the live
/// routine slots (`docs/progress-charts.md`).
struct ExerciseUsagePickerItem: Identifiable, Hashable, Sendable {
    let key: ExerciseUsage.Key
    let label: String

    var id: ExerciseUsage.Key { key }
}

extension ExerciseUsage {
    /// How this usage is named to the user — "4–6 reps · Push A".
    ///
    /// One implementation for the recent-sets badge and the picker: a usage the user
    /// selects by one name and then sees labelled with another is worse than no label.
    ///
    /// The rep range is what usually names a usage, and the routine name distinguishes
    /// two slots that share one — a label of the routine name alone leaves two usages of
    /// one routine both reading "Pull".
    ///
    /// **`.unattributed` always leads with its marker** (2026-08-24). Slot-less rows carry
    /// a denormalized rep-range goal like any other, so a label built from the goal alone
    /// made the bucket read exactly like a routine slot — the reporter's picker offered
    /// `4–6 Wdh. · Pull` twice, one of which was this bucket, and its recent-sets cards
    /// showed `4–6 Wdh. · Pull` and `Ohne Zuordnung · Pull` side by side inside a single
    /// selected usage. Marker first, so a truncated badge still says what it is.
    var displayLabel: String {
        var parts: [String] = []
        switch slot {
        case .routineSlot:
            parts.append(repRangeGoalText ?? "rep_range.no_goal".localized)
        case .unattributed:
            parts.append("history.exercise.usage.unassigned".localized)
            if let repRangeGoalText { parts.append(repRangeGoalText) }
        }
        if !routineName.isEmpty {
            parts.append(routineName)
        }
        return parts.joined(separator: " · ")
    }

    /// The rep-range goal as the user reads it, or nil when the usage carries none.
    /// "Kein Ziel" / "No goal" is the routine editor's own wording for the empty case, so
    /// the label names the setting the user would go and change.
    private var repRangeGoalText: String? {
        // Same wording as the active-workout card's rep-range chip, on purpose.
        repRangeText.map { "workout.exercise.rep_goal".localized($0) }
    }
}

enum ExerciseUsageLabeling {
    /// Day and month of the last workout that trained a usage — "12.07." / "07/12".
    ///
    /// A `Date.FormatStyle` rather than a `DateFormatter`: this type is isolation-agnostic
    /// Domain code, and a `static let DateFormatter` (non-`Sendable`) would not compile
    /// here — the same constraint `ChatFactBuilder` documents. The style is a `Sendable`
    /// value, so it can be hoisted, which is what the rendering rules require: no
    /// formatter is ever built per row or in a view body.
    private static let lastTrainedStyle = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits)

    /// The last-trained date as the user reads it — "12.07." / "07/12".
    ///
    /// Exposed for the empty chart's dated copy, which names the same date the picker
    /// appends when two labels collide. One style, one rendering: a date that read
    /// differently in the two places would look like two different facts.
    static func lastTrainedDateText(_ date: Date) -> String {
        date.formatted(lastTrainedStyle)
    }

    /// Picker entries for one exercise's usages, in the order given.
    ///
    /// Labels that would collide get the usage's **last-trained date** appended
    /// ("· zuletzt 12.07."), because that is what actually tells the entries apart for the
    /// user: which one is the slot their live routine still holds, and which is a leftover
    /// from a routine they have since changed. Ticket 03 appended the row's position in
    /// the workout instead, which failed on the reporter's own data — their two colliding
    /// slots sit at the *same* position, so the tiebreaker collided along with the label.
    ///
    /// If the date does not settle it either, the entry's position in this menu is
    /// appended. That is the one suffix guaranteed unique, since it is drawn from the
    /// list being rendered rather than from anything in the data.
    ///
    /// A usage whose slot no longer lives in any routine leads with a marker instead —
    /// see `baseLabel(for:)`. It is part of the base label, so a marked and an unmarked
    /// usage of the same rep range no longer collide and neither needs the date.
    static func pickerItems(for options: [ExerciseUsageOption]) -> [ExerciseUsagePickerItem] {
        let bases = options.map(baseLabel)

        var baseCounts: [String: Int] = [:]
        for base in bases {
            baseCounts[base, default: 0] += 1
        }

        let dated = zip(options, bases).map { option, base -> String in
            guard (baseCounts[base] ?? 0) > 1 else { return base }
            let date = lastTrainedDateText(option.lastPerformed)
            return base + separator + "chart.usage.last_trained".localized(date)
        }

        var datedCounts: [String: Int] = [:]
        for label in dated {
            datedCounts[label, default: 0] += 1
        }

        return zip(options, dated).enumerated().map { index, pair in
            let (option, label) = pair
            return ExerciseUsagePickerItem(
                key: option.key,
                label: (datedCounts[label] ?? 0) > 1 ? label + separator + "#\(index + 1)" : label
            )
        }
    }

    /// A usage's name in the picker, before any disambiguating suffix.
    ///
    /// An archived usage — one whose routine slot no longer exists anywhere — **leads**
    /// with its marker, for the same reason `.unattributed` does: the picker's collapsed
    /// button is narrow and tail-truncated, so a marker appended after the rep range and
    /// the routine name is exactly the part the user never sees. It says "not in a
    /// routine" rather than "archived" because that is literally what was checked, and it
    /// stays true whether the whole routine was deleted or just this exercise removed
    /// from it.
    ///
    /// The marker only names a usage; it never removes, reorders or merges one. See
    /// `ExerciseUsageOption.isArchived`.
    private static func baseLabel(for option: ExerciseUsageOption) -> String {
        let label = option.usage.displayLabel
        guard option.isArchived else { return label }
        return "chart.usage.archived".localized + separator + label
    }

    /// The one separator every part of a usage label is joined with, matching
    /// `ExerciseUsage.displayLabel`.
    private static let separator = " · "
}

// MARK: - Exercise Usage Selection

/// Which usage the exercise detail screen is charting.
///
/// The chart plots one series at a time. Drawing every usage as its own line was
/// considered and rejected (see `docs/progress-charts.md`): it complicates the
/// tap-to-inspect annotation and the Pro-gated blur, and one series at a time is the
/// clearer read.
///
/// Keyed on `ExerciseUsage.Key` rather than on a whole `ExerciseUsage`, because the
/// rep range and routine name are **denormalized per history row**: editing a slot's
/// rep-range goal changes what later workouts record, and grouping on the whole value
/// would then split one slot into two series halfway through the window.
enum ExerciseUsageSelection: Hashable, Sendable {
    /// Every usage folded together — the behaviour that predates the picker.
    case combined
    case usage(ExerciseUsage.Key)

    /// A stable, filename-safe identifier for this selection, for use inside cache keys.
    ///
    /// The AI Coach's exercise deep-dive narrates the *selected* usage, so its cached
    /// narrative belongs to a `(exercise, usage, last-set timestamp)` triple rather than
    /// to the exercise alone — without the usage in the key, switching usage serves the
    /// previous usage's sentences, and switching back either re-serves them or spends a
    /// second monthly allowance unit (`docs/pro-subscription.md` §5e).
    ///
    /// Lives on the value, not in the cache, so there is one spelling of it: changing
    /// this string silently orphans every cached narrative, which is a decision and not
    /// an implementation detail.
    var cacheToken: String {
        switch self {
        case .combined:
            return "all"
        case .usage(let key):
            switch key.slot {
            case .routineSlot(let id):
                return "\(id.uuidString)#\(key.occurrence)"
            case .unattributed:
                return "unattributed#\(key.occurrence)"
            }
        }
    }
}

/// One entry of the detail screen's usage picker: a usage found anywhere in history,
/// described by the most recent row that belongs to it.
///
/// The options are deliberately **all-time**, not scoped to the charted window: a menu
/// that reshuffled on every timeframe tap is what the reporter described as the screen
/// "suddenly showing different options". A usage with no rows inside the window renders
/// the existing empty-chart state instead of being removed from the menu.
struct ExerciseUsageOption: Identifiable, Hashable, Sendable {
    /// Descriptor taken from the usage's **most recent** row — chosen by an explicit
    /// greatest-`(session.startTime, order, id)` comparison in `ExerciseUsageResolver`,
    /// never by arrival order — so a slot whose rep-range goal changed reads as what the
    /// user last trained, identically on every load.
    let usage: ExerciseUsage
    /// Start of the most recent workout that trained this usage. Both the menu's sort key
    /// and, when two labels collide, what the user tells the entries apart by.
    let lastPerformed: Date
    /// `WorkoutExercise.order` of that most recent row. Orders the menu only — two usages
    /// last trained in the same workout are listed in the sequence they were performed.
    /// It is **not** a disambiguator: two slots can share a position (see
    /// `ExerciseUsageLabeling.pickerItems`).
    let lastPerformedOrder: Int
    /// Whether this usage's routine slot exists in no live routine any more — the user
    /// deleted the routine, or removed (or replaced) this exercise inside it.
    ///
    /// Purely descriptive: an archived usage is never hidden, never reordered and never
    /// merged into a live one. Its workouts happened, so it stays selectable and stays
    /// part of `.combined`; what it needs is to say that the user cannot train it again
    /// without editing a routine (see `docs/progress-charts.md`).
    ///
    /// `.unattributed` is never archived — it has no slot to look up, and its own
    /// "Ohne Zuordnung" marker already says what it is.
    let isArchived: Bool

    init(
        usage: ExerciseUsage,
        lastPerformed: Date,
        lastPerformedOrder: Int,
        isArchived: Bool = false
    ) {
        self.usage = usage
        self.lastPerformed = lastPerformed
        self.lastPerformedOrder = lastPerformedOrder
        self.isArchived = isArchived
    }

    var key: ExerciseUsage.Key { usage.key }
    var slot: ExerciseUsage.Slot { usage.slot }
    var id: ExerciseUsage.Key { usage.key }
}
