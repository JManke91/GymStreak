//
//  FortschrittAggregator.swift
//  GymStreak
//

import Foundation
import SwiftData

/// Pure aggregator that turns completed WorkoutSessions into the row models used by the
/// Fortschritt tab. Pulled into its own type so the heavy per-exercise computation can be
/// called from a background task and the tests can drive it directly.
///
/// The accumulators and the set-level reduction live in `FortschrittAggregator+Fold.swift`.
struct FortschrittAggregator {

    /// Builds one row per *live* exercise in the user's Exercise library.
    ///
    /// Rules:
    /// - Workout exercises whose `exerciseId` matches a live exercise are folded into that row.
    /// - Workout exercises with no `exerciseId` (legacy data) are matched by lowercased name.
    /// - Workout exercises that don't resolve to any live exercise are dropped — this is what
    ///   keeps deleted exercises from leaking into the Progress tab.
    ///
    /// The label a headline carries is built by `ExerciseUsageLabeling.pickerItems` — the
    /// picker's own labeller — so a usage reads the same in the list and on the screen the
    /// list opens. One part does differ: this aggregator has no live routine slot ids, so
    /// its labels never carry the "not in a routine" marker (see `docs/progress-charts.md`),
    /// and where that marker is what separates two otherwise identical usages the row's
    /// label falls back to the date suffix the picker would have used without it.
    ///
    /// The row **summarises one usage**: an exercise trained two ways (heavy in one
    /// routine slot, light in another) would otherwise get one sparkline and one
    /// percentage blended across both, which is the number that read +0.0% over the
    /// reporter's 21 entries. `sparkline` and `trendPct` describe the **most recently
    /// trained** usage — `ExerciseUsageResolver.resolveSelection` decides it, the same call
    /// the detail screen makes — while `workoutCount` stays the exercise's total, because
    /// the list is one row per exercise and that count is what the user reads it as.
    /// See `docs/progress-charts.md`.
    ///
    /// Where two or more live exercises share a display name, every one of them carries
    /// its `equipmentQualifier` so the rows can be told apart; a uniquely named exercise
    /// carries none. Two same-named exercises that also share equipment stay
    /// indistinguishable — see `docs/progress-charts.md`.
    ///
    /// Trend is the % change between the first and last session's heaviest effective
    /// weight, within that one usage — the same metric the detail chart draws by default,
    /// and the only one a free user may read.
    static func build(
        sessions: [WorkoutSession],
        liveExercises: [Exercise]
    ) -> [FortschrittExerciseModel] {
        var liveById: [UUID: Exercise] = [:]
        var liveByName: [String: [Exercise]] = [:]
        for exercise in liveExercises {
            liveById[exercise.id] = exercise
            liveByName[exercise.name.lowercased(), default: []].append(exercise)
        }
        // Resolved once for the whole library, not per row: a row only prints an
        // equipment qualifier where its display name is shared with another live
        // exercise (the reporter's two "Biceps Curls", barbell and dumbbell).
        var equipmentQualifiers: [UUID: EquipmentType] = [:]
        for (_, sharingAName) in liveByName where sharingAName.count > 1 {
            for exercise in sharingAName {
                equipmentQualifiers[exercise.id] = exercise.equipmentType
            }
        }

        let finished = sessions
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        var map: [UUID: Accumulator] = [:]

        for session in finished {
            // Which rows of this workout belong to which live exercise, resolved once.
            // Keying happens per exercise below rather than over the whole workout: the
            // `.unattributed` bucket is shared by every slot-less row, so keying them
            // together would number two different ad-hoc exercises 0 and 1, and the
            // detail screen — which only ever sees one exercise — would disagree.
            var rowIdsByLive: [UUID: Set<UUID>] = [:]

            for workoutExercise in session.workoutExercisesList {
                guard let live = resolveLive(
                    workoutExercise: workoutExercise,
                    byId: liveById,
                    byName: liveByName
                ) else { continue }
                // A library setting only describes future workouts. Keep the
                // progress series homogeneous by excluding older snapshots
                // with a different meaning for the entered number.
                guard workoutExercise.loadBehavior == live.loadBehavior else { continue }

                rowIdsByLive[live.id, default: []].insert(workoutExercise.id)
            }

            for (liveId, rowIds) in rowIdsByLive {
                guard let live = liveById[liveId] else { continue }
                var accumulator = map[liveId] ?? Accumulator(
                    displayName: live.name,
                    muscleGroups: live.muscleGroups,
                    loadBehavior: live.loadBehavior
                )
                var didRecordAnything = false

                // One value per *usage* per session. Before usages existed this folded a
                // workout's repeats of an exercise into a single value, which counted the
                // workout once but still blended two different pieces of work; the keyed
                // rows separate them instead, and a session still contributes at most one
                // value to any one usage because the occurrence index makes a slot's
                // second row a usage of its own.
                for (workoutExercise, key) in ExerciseUsageResolver.keyedRows(in: session, matching: {
                    rowIds.contains($0.id)
                }) {
                    // Filtered **after** keying, exactly as `ExerciseUsageResolver.options`
                    // does it. Dropping a set-less row before the occurrence index is
                    // assigned would shift every later row of that slot by one, so a
                    // workout whose first block was left uncompleted would give the row
                    // occurrence 0 and the picker occurrence 1 — the handed-down usage
                    // would then be absent from the menu and silently fall back.
                    guard workoutExercise.setsList.contains(where: \.isCompleted) else { continue }

                    let fold = foldSets(of: workoutExercise, in: session)
                    let rank = ExerciseUsageResolver.DescriptorRank(
                        startTime: session.startTime,
                        order: workoutExercise.order,
                        id: workoutExercise.id
                    )
                    let descriptor = ExerciseUsageResolver.usage(
                        of: workoutExercise,
                        in: session,
                        occurrence: key.occurrence
                    )

                    var usage = accumulator.usages[key] ?? UsageAccumulator(
                        descriptor: descriptor,
                        descriptorRank: rank,
                        lastPerformed: session.startTime,
                        lastPerformedOrder: workoutExercise.order
                    )
                    // Described by its most recent row, by explicit comparison — the same
                    // rule `ExerciseUsageResolver.options` applies, so the label the row
                    // carries is the label the picker shows for that usage. Taking
                    // whichever row arrived last would make a slot whose rep-range goal
                    // changed read differently in the two places.
                    if rank > usage.descriptorRank {
                        usage.descriptor = descriptor
                        usage.descriptorRank = rank
                        usage.lastPerformed = session.startTime
                        usage.lastPerformedOrder = workoutExercise.order
                    }
                    usage.sessionValues.append((session.startTime, fold))
                    accumulator.usages[key] = usage
                    didRecordAnything = true
                }

                // A workout whose rows were all left uncompleted is not a workout of this
                // exercise, and must not create a row for it either.
                guard didRecordAnything else { continue }

                accumulator.displayName = live.name
                accumulator.muscleGroups = live.muscleGroups
                accumulator.loadBehavior = live.loadBehavior
                // The workout count is the exercise's, across usages: one entry per
                // session, never one per exercise instance (the defect that reported 21
                // workouts for 14 sessions).
                accumulator.sessionCount += 1
                accumulator.lastPerformed = session.startTime
                map[liveId] = accumulator
            }
        }

        let models: [FortschrittExerciseModel] = map.map { id, accumulator in
            let options = ExerciseUsageResolver.sorted(
                accumulator.usages.map { key, usage in
                    ExerciseUsageOption(
                        usage: usage.descriptor,
                        lastPerformed: usage.lastPerformed,
                        lastPerformedOrder: usage.lastPerformedOrder
                    )
                }
            )
            // The headline is whatever the detail screen opens on by itself — the same
            // call, not a second rule — so the row and that screen cannot disagree.
            let headlineKey: ExerciseUsage.Key?
            switch ExerciseUsageResolver.resolveSelection(requested: nil, options: options) {
            case .usage(let key):
                headlineKey = key
            case .combined:
                // Nothing to choose between: that one usage *is* the exercise.
                headlineKey = options.first?.key
            }
            // Labelled through the picker's own labeller, not from the raw descriptor, so
            // two usages sharing a rep range are told apart in the row exactly as they are
            // in the menu ("· zuletzt 12.07.", "· #2"). See below for the one part that
            // still differs.
            // Only when a headline will actually be published — a single-usage row names
            // no usage, so labelling it is work thrown away for every such exercise.
            let labelled = options.count > 1
                ? ExerciseUsageLabeling.pickerItems(for: options)
                : []
            let folds = (headlineKey.flatMap { accumulator.usages[$0]?.sessionValues } ?? [])
                .sorted { $0.date < $1.date }
            // **One value space for the whole series**, decided the same way the detail
            // chart decides it (`ExerciseProgressAggregator.buildProgress`): a single
            // session without a body-mass snapshot values *every* session as raw
            // assistance. Deciding per session — which is what the fold used to do —
            // mixed estimated physical load (tens of kg) with the machine's assistance
            // number in one sparkline, and then inverted both against one baseline, so
            // the direction was wrong for one of them. Raw assistance is the
            // conservative direction: it never manufactures a load from a body weight
            // the user did not record. See `docs/assisted-exercise-progress.md`.
            // Not the same flag as `ExerciseProgressData.usesEffectiveLoad`, which is
            // counterweight-only and therefore `false` for a resistance exercise. This one
            // just says which projection to take, so it is unconditionally true there.
            // `chartsAssistance` below is the value the two surfaces can be compared on.
            let usesEffectiveLoad = !accumulator.loadBehavior.isCounterweightAssistance
                || folds.allSatisfy(\.fold.canUseEffectiveLoad)
            let values = folds.map { $0.fold.value(usingEffectiveLoad: usesEffectiveLoad) }
            let chartsAssistance = accumulator.loadBehavior.isCounterweightAssistance
                && !usesEffectiveLoad
            let sparkline: [Double]
            if chartsAssistance {
                let baseline = values.max() ?? 0
                sparkline = values.map { baseline - $0 }
            } else {
                sparkline = values
            }
            let trend: Double? = {
                guard let first = values.first, let last = values.last,
                      first > 0, values.count >= 2 else { return nil }
                let delta = chartsAssistance ? first - last : last - first
                return (delta / first) * 100
            }()
            return FortschrittExerciseModel(
                id: id.uuidString,
                name: accumulator.displayName,
                primaryMuscleGroup: accumulator.muscleGroups.first ?? "General",
                muscleGroups: accumulator.muscleGroups,
                exerciseId: id,
                workoutCount: accumulator.sessionCount,
                lastPerformed: accumulator.lastPerformed,
                trendPct: trend,
                sparkline: sparkline.isEmpty ? [0] : sparkline,
                usageCount: options.count,
                // Only when there is something behind the headline. A single usage *is*
                // the exercise, and naming it would put a picker label on every row.
                headlineUsage: options.count > 1
                    ? headlineKey.flatMap { key in labelled.first { $0.key == key } }
                    : nil,
                chartsAssistance: chartsAssistance,
                equipmentQualifier: equipmentQualifiers[id]
            )
        }

        return models.sorted { $0.workoutCount > $1.workoutCount }
    }

    /// Resolves a workout exercise to its live library entry. Prefers the stored
    /// `exerciseId` link; falls back to a case-insensitive name match for legacy
    /// rows that pre-date the `exerciseId` field. The fallback is **only** used
    /// when the name is unique in the live library — otherwise the legacy row is
    /// ambiguous (e.g. "Biceps Curls" exists as both dumbbell and barbell entries)
    /// and we drop it rather than misattribute its sets to one variant.
    private static func resolveLive(
        workoutExercise: WorkoutExercise,
        byId: [UUID: Exercise],
        byName: [String: [Exercise]]
    ) -> Exercise? {
        if let id = workoutExercise.exerciseId, let live = byId[id] {
            return live
        }
        let candidates = byName[workoutExercise.exerciseName.lowercased()] ?? []
        return candidates.count == 1 ? candidates[0] : nil
    }
}
