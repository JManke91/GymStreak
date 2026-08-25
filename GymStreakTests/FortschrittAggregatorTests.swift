//
//  FortschrittAggregatorTests.swift
//  GymStreakTests
//
//  Pins the Fortschritt row aggregation to *sessions* rather than exercise
//  instances. The shipped bug: a routine training one exercise twice in a
//  workout appended two same-dated entries, so the row reported 21 workouts for
//  14 sessions, drew a zero-width sawtooth and computed a 0.0% trend.
//
//  Ticket 05 then made the row's series describe **one usage** — the most recently
//  trained one — instead of a fold across all of them, so the assisted cases below
//  assert the headline usage's own numbers rather than a cross-usage fold, and moved
//  the metric from estimated 1RM (Pro-gated) to max weight, which is what the detail
//  chart draws by default.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct FortschrittAggregatorTests {

    /// Two usages of the same exercise in one workout are one workout, and the row's
    /// value belongs to the headline usage — here the first-performed one, since both
    /// have a single session behind them.
    @Test
    func sessionTrainingAnExerciseTwiceCountsOnceAndKeepsTheBetterUsage() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context)
        addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 1)
        #expect(row.sparkline.count == 1)
        // The 20 kg × 5 block, not a fold of both: one session each, so the tie goes to
        // the usage the detail screen opens on — the first one performed.
        #expect(row.sparkline == [20])
        #expect(row.usageCount == 2)
        #expect(row.headlineUsage != nil)
    }

    /// The reporter's shape: every workout trains the exercise heavy *and* light,
    /// with one single-usage workout mixed in. One point per workout, and the
    /// trend must compare comparable ends instead of cancelling to zero.
    @Test
    func mixedSingleAndDoubleUsageSessionsYieldOnePointPerWorkoutWithARealTrend() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        for (index, heavy) in [20.0, 22.0, 24.0].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(heavy, 5, true)], to: session, context: context)
            addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context)
        }
        // A fourth workout that only trains it once — the mix must not change the rule.
        let single = makeSession(startTime: Date(timeIntervalSince1970: 4_000), context: context)
        addExercise(curls, order: 0, sets: [(26, 5, true)], to: single, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 4)
        #expect(row.sparkline.count == 4)
        // Previously the sawtooth: heavy, light, heavy, light … at zero horizontal distance.
        #expect(row.sparkline == row.sparkline.sorted())
        let trend = try #require(row.trendPct)
        // 20 kg → 26 kg of max weight is a +30% gain, not the +0.0% the bug reported.
        #expect(abs(trend - 30) < 0.001)
    }

    /// The row's workout count is the same number the exercise detail screen
    /// shows for the all-time window — the two surfaces read one rule.
    @Test
    func workoutCountMatchesTheDetailScreensSessionCount() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        for index in 0..<3 {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context)
            addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context)
        }
        try context.save()

        let sessions = try fetchSessions(context)
        let row = try #require(
            FortschrittAggregator.build(
                sessions: sessions,
                liveExercises: try context.fetch(FetchDescriptor<Exercise>())
            ).first
        )
        let detail = ExerciseProgressAggregator.buildProgress(
            sessions: sessions,
            exerciseName: curls.name,
            exerciseId: curls.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            startDate: .distantPast
        )

        #expect(row.workoutCount == detail.dataPoints.count)
        #expect(row.workoutCount == 3)
    }

    /// Counterweight assistance without a body-mass snapshot compares raw entered
    /// numbers, where *less* is better. Folding two usages of one workout must take
    /// the least assistance, and the sparkline/trend inversion must survive it.
    @Test
    func assistedSessionsFoldToTheLeastAssistanceAndKeepInvertedSemantics() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let first = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(pullUp, order: 0, sets: [(20, 8, true)], to: first, context: context)
        addExercise(pullUp, order: 1, sets: [(15, 5, true)], to: first, context: context)
        let second = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(pullUp, order: 0, sets: [(12, 8, true)], to: second, context: context)
        addExercise(pullUp, order: 1, sets: [(10, 5, true)], to: second, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 2)
        // Raw assistance, so the row says so rather than calling it a max weight.
        #expect(row.chartsAssistance)
        // The headline usage is the first-performed block (20 kg → 12 kg of assistance);
        // baseline (20) − value, so a rising line still means progress.
        #expect(row.sparkline == [0, 8])
        // 20 kg → 12 kg of assistance is a 40% improvement, not a regression.
        let trend = try #require(row.trendPct)
        #expect(abs(trend - 40) < 0.001)
    }

    /// With a body-mass snapshot the assisted series becomes real effective load,
    /// so the fold flips to "heaviest effective weight" like any resistance exercise.
    @Test
    func assistedSessionWithBodyWeightFoldsToTheHighestEffectiveWeight() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        session.bodyWeightKg = 80
        addExercise(pullUp, order: 0, sets: [(30, 5, true)], to: session, context: context)
        addExercise(pullUp, order: 1, sets: [(20, 5, true)], to: session, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 1)
        // The headline usage's own set: 80 kg of body mass − 30 kg of assistance = 50 kg
        // of effective load. The 20 kg block is the other usage's, and the picker reaches it.
        #expect(row.sparkline == [50])
        #expect(row.usageCount == 2)
        // A snapshot exists, so this is real load and the row names it as a weight.
        #expect(row.chartsAssistance == false)
    }

    /// Every session snapshotted: the series stays in effective load across workouts,
    /// and a *rising* effective weight is a gain like any resistance exercise.
    @Test
    func fullySnapshottedAssistedSeriesStaysInEffectiveLoad() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        for (index, assistance) in [30.0, 20.0].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            session.bodyWeightKg = 80
            addExercise(pullUp, order: 0, sets: [(assistance, 5, true)], to: session, context: context)
        }
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.chartsAssistance == false)
        // 80 − 30 = 50 kg, then 80 − 20 = 60 kg of effective load.
        #expect(row.sparkline == [50, 60])
        let trend = try #require(row.trendPct)
        #expect(abs(trend - 20) < 0.001)
    }

    /// **Ticket 08.** One workout carries a body-mass snapshot and the next does not.
    /// The series must pick a single value space — raw assistance, the conservative one —
    /// rather than putting an estimated 50 kg of physical load and a 20 kg machine
    /// number into the same sparkline and inverting both against one baseline.
    @Test
    func partlySnapshottedAssistedSeriesValuesEverySessionAsRawAssistance() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let snapshotted = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        snapshotted.bodyWeightKg = 80
        addExercise(pullUp, order: 0, sets: [(30, 5, true)], to: snapshotted, context: context)
        let bare = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(pullUp, order: 0, sets: [(20, 5, true)], to: bare, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.chartsAssistance)
        // Raw assistance 30 → 20, inverted against the 30 kg baseline. The 1RM-scale
        // 50 kg (80 − 30) that the snapshotted session *could* have produced must not
        // appear anywhere in the series.
        #expect(row.sparkline == [0, 10])
        #expect(row.sparkline.allSatisfy { $0 < 50 })
        let trend = try #require(row.trendPct)
        // 30 kg → 20 kg of assistance is a 33.3% improvement. Mixing the two spaces
        // reported 60% here, computed from (50 − 20) / 50.
        #expect(abs(trend - (100.0 / 3.0)) < 0.001)
    }

    /// The same mixed history, with the exercise trained twice in the snapshotted
    /// workout: the second block is its own usage, the headline usage still takes one
    /// entry per workout, and the resolved value space applies to all of them.
    @Test
    func partlySnapshottedSeriesKeepsOneEntryPerWorkoutWhenTrainedTwice() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let snapshotted = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        snapshotted.bodyWeightKg = 80
        addExercise(pullUp, order: 0, sets: [(30, 5, true)], to: snapshotted, context: context)
        addExercise(pullUp, order: 1, sets: [(25, 8, true)], to: snapshotted, context: context)
        let bare = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(pullUp, order: 0, sets: [(20, 5, true)], to: bare, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.workoutCount == 2)
        #expect(row.usageCount == 2)
        // The headline usage is the first block, the only one trained in both workouts.
        #expect(row.sparkline == [0, 10])
        #expect(row.chartsAssistance)
    }

    /// Tapping the row must not change the unit under the user: the list and the detail
    /// screen's all-time window resolve the same value space for the same history.
    @Test
    func partlySnapshottedRowMatchesTheDetailScreensValueSpace() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let pullUp = Exercise(name: "Assisted Pull-Up", loadBehavior: .counterweightAssistance)
        context.insert(pullUp)

        let snapshotted = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        snapshotted.bodyWeightKg = 80
        addExercise(pullUp, order: 0, sets: [(30, 5, true)], to: snapshotted, context: context)
        let bare = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(pullUp, order: 0, sets: [(20, 5, true)], to: bare, context: context)
        try context.save()

        let row = try #require(try build(context).first)
        let detail = detailSnapshot(pullUp, context: context, requesting: nil).data

        #expect(row.chartsAssistance == !detail.usesEffectiveLoad)
        let charted = detail.dataPoints.map(\.maxWeight)
        let baseline = try #require(charted.max())
        #expect(row.sparkline == charted.map { baseline - $0 })
    }

    /// A resistance exercise never reaches the value-space decision: a workout without a
    /// body-mass snapshot is the normal case there and must stay a plain max weight.
    @Test
    func resistanceSeriesIsUnaffectedByMissingBodyWeightSnapshots() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let press = Exercise(name: "Bench Press")
        context.insert(press)

        let first = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        first.bodyWeightKg = 80
        addExercise(press, order: 0, sets: [(60, 5, true)], to: first, context: context)
        let second = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(press, order: 0, sets: [(70, 5, true)], to: second, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.chartsAssistance == false)
        #expect(row.sparkline == [60, 70])
        let trend = try #require(row.trendPct)
        #expect(abs(trend - (100.0 / 6.0)) < 0.001)
    }

    // MARK: - Several usages behind one row

    /// The row's sparkline and trend describe the **most recently trained** usage rather
    /// than a blend of every usage, while the workout count stays the exercise's own — the
    /// list is one row per exercise and that count is what a user reads it as.
    ///
    /// Recency, not session count, is the rule (changed 2026-08-24 after the on-device
    /// check): the reporter's legacy `Ohne Zuordnung` buckets hold the most sessions of
    /// almost every exercise, so a most-trained headline pointed every row at work last
    /// done in July and opened the detail screen on an empty 1M window.
    @Test
    func theRowHeadlinesTheMostRecentlyTrainedUsageAndStillCountsEveryWorkout() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)
        let heavySlot = UUID()
        let lightSlot = UUID()

        // An old heavy block with more sessions than anything else…
        for (index, weight) in [20.0, 22.0, 24.0].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                routineName: "Pull",
                context: context
            )
            addExercise(curls, order: 0, sets: [(weight, 5, true)], to: session, context: context,
                        routineExerciseId: heavySlot, targetRepMin: 4, targetRepMax: 6)
        }
        // …and the light block the user actually trains now.
        for (index, weight) in [14.0, 15.0].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(4_000 + 1_000 * index)),
                routineName: "Pull",
                context: context
            )
            addExercise(curls, order: 0, sets: [(weight, 12, true)], to: session, context: context,
                        routineExerciseId: lightSlot, targetRepMin: 8, targetRepMax: 12)
        }
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.usageCount == 2)
        #expect(row.headlineUsage?.key == .routineSlot(lightSlot))
        // Every workout of the exercise, not just the headline usage's.
        #expect(row.workoutCount == 5)
        // The curve ends where the row says the exercise was last trained — with the
        // most-recent rule those are the same date, so the row cannot read "yesterday"
        // over a line that stops in July.
        #expect(row.lastPerformed == Date(timeIntervalSince1970: 5_000))
        #expect(row.sparkline.count == 2)
        let trend = try #require(row.trendPct)
        // 14 → 15 kg for 12 reps, within that usage alone.
        #expect(trend > 0)

        // The headline is exactly what the detail screen opens on, named the same way.
        let snapshot = detailSnapshot(curls, context: context, requesting: nil)
        #expect(snapshot.selectedUsage == .usage(try #require(row.headlineUsage?.key)))
        let item = try #require(
            ExerciseUsageLabeling.pickerItems(for: snapshot.availableUsages)
                .first { $0.key == row.headlineUsage?.key }
        )
        #expect(row.headlineUsage?.label == item.label)
    }

    /// One usage and the row is exactly what it was before usages existed: no headline to
    /// name, and the whole history in the sparkline.
    @Test
    func aSingleUsageRowCarriesNoHeadlineAndKeepsItsWholeSeries() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)
        let slot = UUID()

        for (index, weight) in [20.0, 22.0, 24.0].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(weight, 5, true)], to: session, context: context,
                        routineExerciseId: slot)
        }
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.usageCount == 1)
        #expect(row.headlineUsage == nil)
        #expect(row.workoutCount == 3)
        #expect(row.sparkline.count == 3)
    }

    /// The row hands its headline usage to the screen it opens, so the two cannot tell
    /// different stories about the same exercise on first render.
    @Test
    func tappingTheRowOpensTheDetailScreenOnTheSeriesTheRowDrew() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)
        let heavySlot = UUID()
        let lightSlot = UUID()

        // The recent block is trained on days 1, 3 and 5, the older one in between, so the
        // headline series is interleaved rather than simply the tail of history.
        for (day, weight) in [(1, 12.0), (3, 13.0), (5, 14.0)] {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(day) * 1_000),
                context: context
            )
            addExercise(curls, order: 0, sets: [(weight, 10, true)], to: session, context: context,
                        routineExerciseId: lightSlot)
        }
        for (day, weight) in [(2, 20.0), (4, 22.0)] {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(day) * 1_000),
                context: context
            )
            addExercise(curls, order: 0, sets: [(weight, 5, true)], to: session, context: context,
                        routineExerciseId: heavySlot)
        }
        try context.save()

        let row = try #require(try build(context).first)
        let headline = try #require(row.headlineUsage)
        let snapshot = detailSnapshot(curls, context: context, requesting: .usage(headline.key))

        #expect(headline.key == .routineSlot(lightSlot))
        #expect(snapshot.selectedUsage == .usage(headline.key))
        // The same numbers, not merely the same shape: the row folds each session exactly
        // as `buildProgress` folds its `maxWeight` point, so the sparkline *is* the chart's
        // series for that usage.
        #expect(snapshot.data.dataPoints.map(\.maxWeight) == [12, 13, 14])
        #expect(row.sparkline == snapshot.data.dataPoints.map(\.maxWeight))
        #expect(row.workoutCount == 5)
    }

    /// The headline is not a second rule: it is `resolveSelection`'s own answer, so it
    /// lands on exactly the usage the detail screen opens on unaided.
    @Test
    func aTiedHeadlineLandsOnTheUsageTheDetailScreenOpensOnByItself() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)
        let heavySlot = UUID()
        let lightSlot = UUID()

        for (index, slot) in [heavySlot, heavySlot, lightSlot, lightSlot].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context,
                        routineExerciseId: slot)
        }
        try context.save()

        let row = try #require(try build(context).first)
        let unaided = detailSnapshot(curls, context: context, requesting: nil)

        #expect(row.headlineUsage?.key == .routineSlot(lightSlot))
        #expect(unaided.selectedUsage == .usage(try #require(row.headlineUsage?.key)))
    }

    /// The `.unattributed` bucket is shared by every slot-less row, so keying a whole
    /// workout at once would number two different ad-hoc exercises 0 and 1 and invent a
    /// second usage the detail screen — which only ever sees one exercise — never offers.
    @Test
    func adHocRowsOfDifferentExercisesEachKeepTheirOwnUnattributedUsage() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        let rows = Exercise(name: "Cable Rows")
        context.insert(curls)
        context.insert(rows)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context)
        addExercise(rows, order: 1, sets: [(50, 10, true)], to: session, context: context)
        try context.save()

        let built = try build(context)

        #expect(built.count == 2)
        #expect(built.allSatisfy { $0.usageCount == 1 })
        #expect(built.allSatisfy { $0.headlineUsage == nil })
        #expect(detailSnapshot(rows, context: context, requesting: nil).availableUsages.map(\.slot) == [.unattributed])
    }

    /// Two usages the rep range cannot tell apart are told apart in the row exactly as
    /// they are in the picker — the row labels through the picker's own labeller rather
    /// than from the raw descriptor, so the suffix that disambiguates them is not dropped.
    @Test
    func aCollidingHeadlineLabelCarriesTheSameSuffixThePickerGivesIt() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)
        let slotA = UUID()
        let slotB = UUID()

        // Same rep goal, same routine name, different slots — and A trained last, so it
        // is the headline.
        for (index, slot) in [slotB, slotA, slotA].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                routineName: "Pull",
                context: context
            )
            addExercise(curls, order: 0, sets: [(20, 5, true)], to: session, context: context,
                        routineExerciseId: slot, targetRepMin: 4, targetRepMax: 6)
        }
        try context.save()

        let row = try #require(try build(context).first)
        let headline = try #require(row.headlineUsage)
        let snapshot = detailSnapshot(curls, context: context, requesting: .usage(headline.key))
        let item = try #require(
            ExerciseUsageLabeling.pickerItems(for: snapshot.availableUsages)
                .first { $0.key == headline.key }
        )

        #expect(headline.key == .routineSlot(slotA))
        #expect(headline.label == item.label)
        // The bare descriptor would have been ambiguous — that is the point of the suffix.
        #expect(headline.label != ExerciseUsage(
            key: .routineSlot(slotA), targetRepMin: 4, targetRepMax: 6, routineName: "Pull"
        ).displayLabel)
    }

    /// The occurrence index must be assigned over the same rows the picker keys, or a
    /// workout whose first block was left uncompleted numbers the surviving block 0 here
    /// and 1 there — and the usage handed to the detail screen would not exist in its menu.
    @Test
    func aSetLessRowStillCountsTowardsTheOccurrenceIndexJustAsThePickerCountsIt() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)
        let slot = UUID()

        // One slot, two rows in the workout; the first was never completed.
        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(curls, order: 0, sets: [(20, 5, false)], to: session, context: context,
                    routineExerciseId: slot)
        addExercise(curls, order: 1, sets: [(14, 12, true)], to: session, context: context,
                    routineExerciseId: slot)
        // A second slot, so the row has a headline to hand down at all.
        addExercise(curls, order: 2, sets: [(30, 8, true)], to: session, context: context,
                    routineExerciseId: UUID())
        try context.save()

        let row = try #require(try build(context).first)
        let snapshot = detailSnapshot(curls, context: context, requesting: nil)
        let completedKey = ExerciseUsage.Key(slot: .routineSlot(slot), occurrence: 1)

        // The surviving block is that slot's *second* row on both surfaces.
        #expect(snapshot.availableUsages.map(\.key).contains(completedKey))
        #expect(row.usageCount == snapshot.availableUsages.count)
        let headline = try #require(row.headlineUsage)
        #expect(snapshot.availableUsages.map(\.key).contains(headline.key))
        // …so the handed-down usage is one the detail screen can actually select.
        #expect(
            detailSnapshot(curls, context: context, requesting: .usage(headline.key)).selectedUsage
                == .usage(headline.key)
        )
    }

    /// A workout whose every row of this exercise was left uncompleted is not a workout of
    /// it: no value, no count — and for an exercise with no completed set anywhere, no row.
    @Test
    func aWorkoutWithNoCompletedSetOfTheExerciseIsNotCounted() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        let skipped = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(curls, order: 0, sets: [(20, 5, false)], to: skipped, context: context)
        try context.save()
        #expect(try build(context).isEmpty)

        let done = makeSession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(curls, order: 0, sets: [(20, 5, true)], to: done, context: context)
        try context.save()

        let row = try #require(try build(context).first)
        #expect(row.workoutCount == 1)
        #expect(row.lastPerformed == Date(timeIntervalSince1970: 2_000))
    }

    /// The row's number is **max weight**, not estimated 1RM: 1RM is a Pro-gated metric
    /// (`ProFeatureCaps.freeChartMetric` is `.maxWeight`), so a 1RM-derived curve in the
    /// free list handed out something the screen it opens keeps behind a lock. Reps
    /// therefore no longer move the row at all.
    @Test
    func theRowMeasuresMaxWeightSoRepsDoNotMoveIt() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls")
        context.insert(curls)

        // Same weight throughout, rising reps — a 1RM series would climb, a max-weight
        // series is flat, and the trend must read 0.0%.
        for (index, reps) in [5, 8, 12].enumerated() {
            let session = makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(curls, order: 0, sets: [(20, reps, true)], to: session, context: context)
        }
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.sparkline == [20, 20, 20])
        #expect(row.trendPct == 0)
        #expect(row.chartsAssistance == false)
    }

    // MARK: - Same-named exercises (ticket 06)

    /// The reporter's library: two genuinely different exercises that share a name. Both
    /// rows must name their equipment, or the user reads two identical rows carrying
    /// different numbers.
    @Test
    func twoLibraryExercisesSharingANameBothCarryTheirEquipment() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        // Case-insensitively the same name — the collision must not depend on casing.
        let dumbbell = Exercise(name: "biceps curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(barbell, order: 0, sets: [(40, 8, true)], to: session, context: context)
        addExercise(dumbbell, order: 1, sets: [(14, 12, true)], to: session, context: context)
        try context.save()

        let rows = try build(context)

        #expect(rows.count == 2)
        let barbellRow = try #require(rows.first { $0.exerciseId == barbell.id })
        let dumbbellRow = try #require(rows.first { $0.exerciseId == dumbbell.id })
        #expect(barbellRow.equipmentQualifier == .barbell)
        #expect(dumbbellRow.equipmentQualifier == .dumbbell)
    }

    /// The overwhelmingly common case: a unique name gets no qualifier, so the list is
    /// not cluttered with a redundant one.
    @Test
    func aUniquelyNamedExerciseCarriesNoQualifier() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let press = Exercise(name: "Bench Press", equipmentType: .barbell)
        context.insert(curls)
        context.insert(press)

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(curls, order: 0, sets: [(40, 8, true)], to: session, context: context)
        try context.save()

        let row = try #require(try build(context).first)

        #expect(row.exerciseId == curls.id)
        #expect(row.equipmentQualifier == nil)
    }

    /// Three entries under one name: every one of them is qualified, not just the two
    /// that a pairwise check would find.
    @Test
    func threeExercisesSharingANameAreAllQualified() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let variants: [(Exercise, Double)] = [
            (Exercise(name: "Biceps Curls", equipmentType: .barbell), 40),
            (Exercise(name: "Biceps Curls", equipmentType: .dumbbell), 14),
            (Exercise(name: "Biceps Curls", equipmentType: .cable), 25)
        ]
        for (exercise, _) in variants { context.insert(exercise) }

        let session = makeSession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        for (index, variant) in variants.enumerated() {
            addExercise(
                variant.0,
                order: index,
                sets: [(variant.1, 8, true)],
                to: session,
                context: context
            )
        }
        try context.save()

        let rows = try build(context)

        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.equipmentQualifier != nil })
        #expect(
            Set(rows.compactMap(\.equipmentQualifier)) == Set([.barbell, .dumbbell, .cable])
        )
    }

    // MARK: - Fixtures

    /// The exercise detail screen's snapshot for the same history, so a test can assert
    /// the two surfaces agree rather than restating one of them.
    private func detailSnapshot(
        _ exercise: Exercise,
        context: ModelContext,
        requesting selection: ExerciseUsageSelection?
    ) -> ExerciseProgressSnapshot {
        ExerciseProgressAggregator.buildSnapshot(
            sessions: (try? fetchSessions(context)) ?? [],
            liveExercises: (try? context.fetch(FetchDescriptor<Exercise>())) ?? [],
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            startDate: .distantPast,
            recentSessionLimit: 8,
            requestedUsage: selection
        )
    }

    private func build(_ context: ModelContext) throws -> [FortschrittExerciseModel] {
        FortschrittAggregator.build(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>())
        )
    }

    private func fetchSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endTime != nil })
        )
    }

    private func makeSession(
        startTime: Date,
        routineName: String = "",
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        session.routineName = routineName
        context.insert(session)
        return session
    }

    private func addExercise(
        _ exercise: Exercise,
        order: Int,
        sets: [(Double, Int, Bool)],
        to session: WorkoutSession,
        context: ModelContext,
        routineExerciseId: UUID? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil
    ) {
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: order,
            exerciseId: exercise.id,
            routineExerciseId: routineExerciseId,
            loadBehavior: exercise.loadBehavior
        )
        workoutExercise.targetRepMin = targetRepMin
        workoutExercise.targetRepMax = targetRepMax
        workoutExercise.workoutSession = session
        context.insert(workoutExercise)

        for (index, entry) in sets.enumerated() {
            let set = WorkoutSet(
                plannedReps: entry.1,
                actualReps: entry.1,
                plannedWeight: entry.0,
                actualWeight: entry.0,
                restTime: 60,
                order: index
            )
            set.isCompleted = entry.2
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
    }
}
