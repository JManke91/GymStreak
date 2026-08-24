//
//  ExerciseProgressAggregatorTests.swift
//  GymStreakTests
//
//  Coverage for the pure chart aggregation extracted from `ExerciseProgressService`
//  (audit P1.2). The logic shipped with none: `fetchProgressData` had zero tests, so
//  the extraction is pinned here rather than trusted.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseProgressAggregatorTests {

    @Test
    func buildsOneDataPointPerSessionAggregatingItsCompletedSets() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        makeSession(
            startTime: Date(timeIntervalSince1970: 1_000),
            sets: [(weight: 100, reps: 5, completed: true), (weight: 90, reps: 8, completed: true)],
            exercise: exercise,
            context: context
        )
        makeSession(
            startTime: Date(timeIntervalSince1970: 2_000),
            sets: [(weight: 110, reps: 5, completed: true)],
            exercise: exercise,
            context: context
        )
        try context.save()

        let result = ExerciseProgressAggregator.buildProgress(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            startDate: .distantPast
        )

        #expect(result.dataPoints.count == 2)
        // Ascending by date regardless of the fetch order the store hands over —
        // the chart's trend reads first vs. last.
        #expect(result.dataPoints[0].date < result.dataPoints[1].date)
        #expect(result.dataPoints[0].maxWeight == 100)
        #expect(result.dataPoints[0].totalVolume == 100 * 5 + 90 * 8)
        #expect(result.dataPoints[0].totalSets == 2)
        #expect(result.dataPoints[0].totalReps == 13)
        #expect(result.dataPoints[1].maxWeight == 110)
    }

    @Test
    func incompleteSetsAndSessionsOutsideTheWindowAreExcluded() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        makeSession(
            startTime: Date(timeIntervalSince1970: 1_000),
            sets: [(weight: 200, reps: 5, completed: true)],
            exercise: exercise,
            context: context
        )
        makeSession(
            startTime: Date(timeIntervalSince1970: 5_000),
            sets: [(weight: 100, reps: 5, completed: true), (weight: 999, reps: 1, completed: false)],
            exercise: exercise,
            context: context
        )
        try context.save()

        let result = ExerciseProgressAggregator.buildProgress(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            startDate: Date(timeIntervalSince1970: 4_000)
        )

        #expect(result.dataPoints.count == 1)
        #expect(result.dataPoints[0].maxWeight == 100)
        #expect(result.dataPoints[0].totalSets == 1)
    }

    /// The legacy name fallback must stay gated on library uniqueness — an untagged
    /// row is ambiguous when two live exercises share a name, so it belongs to neither.
    @Test
    func ambiguousLegacyRowsAreDroppedWhenTheNameIsNotUnique() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let session = WorkoutSession(routine: nil)
        session.startTime = Date(timeIntervalSince1970: 1_000)
        session.endTime = Date(timeIntervalSince1970: 1_600)
        context.insert(session)
        // No `exerciseId` — a pre-tagging history row.
        addExercise(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: session, context: context)
        try context.save()

        let liveExercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(ExerciseProgressAggregator.isNameUnique("Biceps Curls", in: liveExercises) == false)

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: liveExercises,
            exerciseName: "Biceps Curls",
            exerciseId: barbell.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        #expect(snapshot.data.dataPoints.isEmpty)
        #expect(snapshot.recentUsages.isEmpty)
    }

    @Test
    func recentUsagesAreNewestFirstAndCappedByTheSessionLimit() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        for index in 0..<5 {
            makeSession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                sets: [(weight: Double(100 + index), reps: 5, completed: true)],
                exercise: exercise,
                context: context
            )
        }
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentUsages(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            limit: 3
        )

        #expect(result.count == 3)
        #expect(result[0].date > result[1].date)
        #expect(result[0].bestSet?.weight == 104)
        // Ignores the chart window on purpose — the list is all-time.
        #expect(result[2].bestSet?.weight == 102)
    }

    /// The recent-sets list must never carry a card with no completed sets:
    /// the screen renders each as a card of set chips.
    @Test
    func recentUsagesSkipSessionsWithoutCompletedSets() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        makeSession(
            startTime: Date(timeIntervalSince1970: 2_000),
            sets: [(weight: 100, reps: 5, completed: false)],
            exercise: exercise,
            context: context
        )
        makeSession(
            startTime: Date(timeIntervalSince1970: 1_000),
            sets: [(weight: 80, reps: 5, completed: true)],
            exercise: exercise,
            context: context
        )
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentUsages(
            sessions: try fetchSessions(context),
            exerciseName: "Bench Press",
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            limit: 8
        )

        #expect(result.count == 1)
        #expect(result[0].sets.count == 1)
        #expect(result[0].sets[0].weight == 80)
    }

    // MARK: - Recent usages: one card per usage

    /// The reported contradiction: the chart plotted the heavy usage's 20 kg for a day
    /// whose "recent sets" card showed the light usage's 14 kg × 12. The card kept
    /// `workoutExercisesList.first(where:)` and dropped the rest of the session.
    /// Ticket 03 made the *default* selection one usage rather than the combined view,
    /// so this asks for `.combined` explicitly: the guarantee is that nothing is dropped
    /// when no usage filters the list, not that the screen opens unfiltered.
    @Test
    func aSessionTrainedTwiceYieldsOneCardPerUsageAgreeingWithTheChart() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let heavySlot = UUID()
        let lightSlot = UUID()
        let session = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        session.routineName = "Push A"
        addExercise(
            named: exercise.name, exerciseId: exercise.id,
            sets: [(20, 5, true), (20, 5, true), (20, 4, true)],
            to: session, context: context,
            order: 0, routineExerciseId: heavySlot, targetRepMin: 4, targetRepMax: 6
        )
        addExercise(
            named: exercise.name, exerciseId: exercise.id,
            sets: [(14, 12, true), (14, 10, true), (14, 8, true)],
            to: session, context: context,
            order: 1, routineExerciseId: lightSlot, targetRepMin: 8, targetRepMax: 12
        )
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            startDate: .distantPast,
            recentSessionLimit: 8,
            requestedUsage: .combined
        )

        // Both blocks survive, and neither is interleaved with the other.
        #expect(snapshot.recentUsages.count == 2)
        #expect(snapshot.recentUsages.allSatisfy { $0.workoutSessionId == session.id })
        #expect(snapshot.recentUsages[0].sets.map(\.weight) == [20, 20, 20])
        #expect(snapshot.recentUsages[0].sets.map(\.reps) == [5, 5, 4])
        #expect(snapshot.recentUsages[1].sets.map(\.weight) == [14, 14, 14])
        #expect(snapshot.recentUsages[1].sets.map(\.reps) == [12, 10, 8])

        // Each card names the usage behind it.
        #expect(snapshot.recentUsages[0].usage.slot == .routineSlot(heavySlot))
        #expect(snapshot.recentUsages[0].usage.repRangeText == "4–6")
        #expect(snapshot.recentUsages[1].usage.slot == .routineSlot(lightSlot))
        #expect(snapshot.recentUsages[1].usage.repRangeText == "8–12")
        #expect(snapshot.recentUsages.allSatisfy { $0.usage.routineName == "Push A" })

        // The panels no longer contradict each other about the same workout: the
        // heaviest set the list shows is the value the chart plots for that day.
        #expect(snapshot.data.dataPoints.count == 1)
        let heaviestShown = snapshot.recentUsages.compactMap { $0.bestSet?.weight }.max()
        #expect(heaviestShown == snapshot.data.dataPoints[0].maxWeight)
        #expect(heaviestShown == 20)
    }

    /// Block order comes from `WorkoutExercise.order` — the sequence the user performed —
    /// never from whatever order the `workoutExercises` to-many relationship materialises.
    /// The two sessions here are inserted in opposite orders from their `order` values, so
    /// the assertions cannot pass by inheriting the array.
    @Test
    func blockOrderFollowsWorkoutExerciseOrderNotTheRelationshipArray() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        // Inserted light-first, but the user performed heavy first (order 0).
        let newer = makeEmptySession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: newer, context: context, order: 1, routineExerciseId: UUID())
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: newer, context: context, order: 0, routineExerciseId: UUID())

        // Inserted heavy-first, but the user performed light first (order 0).
        let older = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: older, context: context, order: 1, routineExerciseId: UUID())
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: older, context: context, order: 0, routineExerciseId: UUID())
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentUsages(
            sessions: try fetchSessions(context),
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            limit: 8
        )

        #expect(result.count == 4)
        // Newest session first, and within it the performed order.
        #expect(result.map { $0.bestSet?.weight } == [20, 14, 14, 20])
        #expect(result[0].workoutSessionId == newer.id)
        #expect(result[1].workoutSessionId == newer.id)
        #expect(result[2].workoutSessionId == older.id)
        #expect(result[3].workoutSessionId == older.id)
    }

    /// The cap bounds **sessions**, not cards: showing every usage must not shrink how
    /// far back the list reaches.
    @Test
    func theLimitCapsSessionsWhileASessionMayContributeSeveralCards() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        // Four sessions, each trained twice, plus one single-usage session in the middle.
        for index in 0..<4 {
            let session = makeEmptySession(
                startTime: Date(timeIntervalSince1970: Double(1_000 * (index + 1))),
                context: context
            )
            addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                        to: session, context: context, order: 0, routineExerciseId: UUID())
            if index != 1 {
                addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                            to: session, context: context, order: 1, routineExerciseId: UUID())
            }
        }
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentUsages(
            sessions: try fetchSessions(context),
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            limit: 3
        )

        // 3 sessions deep — the two-usage ones contribute two cards, the single one card.
        #expect(Set(result.map(\.workoutSessionId)).count == 3)
        #expect(result.count == 5)
    }

    /// Legacy history and ad-hoc exercises carry no `routineExerciseId`. They belong to
    /// an explicit bucket — never dropped, never folded into a real slot.
    @Test
    func rowsWithoutARoutineSlotResolveToTheUnattributedBucket() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let session = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        session.routineName = "Push A"
        // A pre-`routineExerciseId` row: no slot, and no rep-range goal either.
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(15, 12, true)],
                    to: session, context: context, order: 0)
        try context.save()

        let result = ExerciseProgressAggregator.buildRecentUsages(
            sessions: try fetchSessions(context),
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            nameIsUnique: true,
            loadBehavior: .resistance,
            limit: 8
        )

        #expect(result.count == 1)
        #expect(result[0].usage.slot == .unattributed)
        #expect(result[0].usage.repRangeText == nil)
        #expect(result[0].usage.routineName == "Push A")
    }

    /// Deliberate change: the list applies the chart's `loadBehavior` filter, which it
    /// used not to. A row the chart excluded must not reappear underneath it.
    @Test
    func recentUsagesApplyTheChartsLoadBehaviourFilter() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Pull-Up")
        context.insert(exercise)

        let session = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(0, 8, true)],
                    to: session, context: context, order: 0, routineExerciseId: UUID())
        // Recorded back when the library exercise was still counterweight-assisted.
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(30, 8, true)],
                    to: session, context: context, order: 1, routineExerciseId: UUID(),
                    loadBehavior: .counterweightAssistance)
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        #expect(snapshot.recentUsages.count == 1)
        #expect(snapshot.recentUsages[0].sets[0].weight == 0)
        #expect(snapshot.data.dataPoints.count == 1)
    }

    // MARK: - Usage selection (ticket 03)

    /// The reported bug: Biceps Curls trained 20 kg for 4–6 in one routine and 14 kg for
    /// 8–12 in another, on alternating days. Combined, the series alternates between the
    /// two loads; per usage, each reads as a progression.
    @Test
    func selectingAUsageChartsOnlyThatRoutineSlot() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let heavySlot = UUID()
        let lightSlot = UUID()
        let schedule: [(day: Int, slot: UUID, weight: Double, reps: Int)] = [
            (1, heavySlot, 20, 5),
            (2, lightSlot, 14, 12),
            (3, heavySlot, 22.5, 5),
            (4, lightSlot, 15, 12)
        ]
        for entry in schedule {
            let session = makeEmptySession(
                startTime: Date(timeIntervalSince1970: Double(entry.day) * 1_000),
                context: context
            )
            session.routineName = entry.slot == heavySlot ? "Pull A" : "Pull B"
            addExercise(
                named: exercise.name, exerciseId: exercise.id,
                sets: [(entry.weight, entry.reps, true)],
                to: session, context: context,
                order: 0, routineExerciseId: entry.slot,
                targetRepMin: entry.slot == heavySlot ? 4 : 8,
                targetRepMax: entry.slot == heavySlot ? 6 : 12
            )
        }
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        let heavy = ExerciseProgressAggregator.buildSnapshot(
            sessions: sessions, liveExercises: live,
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: .usage(.routineSlot(heavySlot))
        )
        #expect(heavy.selectedUsage == .usage(.routineSlot(heavySlot)))
        #expect(heavy.data.dataPoints.map(\.maxWeight) == [20, 22.5])
        // Which is the whole point: a progression, not a sawtooth.
        #expect(heavy.data.progressPercentage(for: .maxWeight) == 12.5)
        #expect(heavy.recentUsages.allSatisfy { $0.usage.slot == .routineSlot(heavySlot) })

        let light = ExerciseProgressAggregator.buildSnapshot(
            sessions: sessions, liveExercises: live,
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: .usage(.routineSlot(lightSlot))
        )
        #expect(light.data.dataPoints.map(\.maxWeight) == [14, 15])

        // Combined is still available, and is still the alternating curve that was filed.
        let combined = ExerciseProgressAggregator.buildSnapshot(
            sessions: sessions, liveExercises: live,
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: .combined
        )
        #expect(combined.selectedUsage == .combined)
        #expect(combined.data.dataPoints.map(\.maxWeight) == [20, 14, 22.5, 15])
    }

    /// A workout containing the exercise twice contributes a point to *each* usage
    /// instead of collapsing into one `max` that describes neither.
    @Test
    func aWorkoutTrainedTwiceContributesAPointToEachOfItsUsages() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let heavySlot = UUID()
        let lightSlot = UUID()
        let session = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        session.routineName = "Pull"
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: session, context: context, order: 0, routineExerciseId: heavySlot,
                    targetRepMin: 4, targetRepMax: 6)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: session, context: context, order: 1, routineExerciseId: lightSlot,
                    targetRepMin: 8, targetRepMax: 12)
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        func snapshot(_ selection: ExerciseUsageSelection) -> ExerciseProgressSnapshot {
            ExerciseProgressAggregator.buildSnapshot(
                sessions: sessions, liveExercises: live,
                exerciseName: exercise.name, exerciseId: exercise.id,
                startDate: .distantPast, recentSessionLimit: 8,
                requestedUsage: selection
            )
        }

        #expect(snapshot(.usage(.routineSlot(heavySlot))).data.dataPoints.map(\.maxWeight) == [20])
        #expect(snapshot(.usage(.routineSlot(lightSlot))).data.dataPoints.map(\.maxWeight) == [14])
        // Unchanged for anyone who wants the old reading — one point, the session max.
        #expect(snapshot(.combined).data.dataPoints.map(\.maxWeight) == [20])
    }

    /// Opening on the combined view would show the reporter the exact sawtooth they
    /// filed, so the screen opens on the usage they trained most recently.
    @Test
    func theDefaultSelectionIsTheMostRecentlyTrainedUsage() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let olderSlot = UUID()
        let newerSlot = UUID()
        let older = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: older, context: context, order: 0, routineExerciseId: olderSlot)
        let newer = makeEmptySession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: newer, context: context, order: 0, routineExerciseId: newerSlot)
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: nil
        )

        #expect(snapshot.selectedUsage == .usage(.routineSlot(newerSlot)))
        #expect(snapshot.availableUsages.map(\.slot) == [.routineSlot(newerSlot), .routineSlot(olderSlot)])
        #expect(snapshot.data.dataPoints.map(\.maxWeight) == [14])
    }

    /// One usage and there is nothing to choose between: the screen stays on the
    /// combined series, which is that usage's series, and the picker stays hidden.
    @Test
    func aSingleUsageResolvesToTheCombinedSeries() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let session = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(100, 5, true)],
                    to: session, context: context, order: 0, routineExerciseId: UUID())
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: nil
        )

        #expect(snapshot.availableUsages.count == 1)
        #expect(snapshot.selectedUsage == .combined)
    }

    /// The slot id is denormalized into history precisely so it survives the routine
    /// being edited or deleted — charting one usage must not need the routine to exist.
    @Test
    func aSlotWhoseRoutineWasDeletedStillChartsAsItsOwnUsage() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let deletedRoutineSlot = UUID()
        let liveSlot = UUID()
        for day in 1...2 {
            let session = makeEmptySession(
                startTime: Date(timeIntervalSince1970: Double(day) * 1_000),
                context: context
            )
            // `routine` is nil — the routine is gone — but the workout kept its name
            // and the row kept the slot id.
            session.routineName = "Deleted Pull"
            addExercise(named: exercise.name, exerciseId: exercise.id,
                        sets: [(Double(20 + day), 5, true)],
                        to: session, context: context, order: 0,
                        routineExerciseId: deletedRoutineSlot, targetRepMin: 4, targetRepMax: 6)
        }
        let current = makeEmptySession(startTime: Date(timeIntervalSince1970: 3_000), context: context)
        current.routineName = "Pull"
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: current, context: context, order: 0, routineExerciseId: liveSlot)
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: .usage(.routineSlot(deletedRoutineSlot))
        )

        #expect(snapshot.data.dataPoints.map(\.maxWeight) == [21, 22])
        let option = snapshot.availableUsages.first { $0.slot == .routineSlot(deletedRoutineSlot) }
        #expect(option?.usage.routineName == "Deleted Pull")
        #expect(option?.usage.repRangeText == "4–6")
    }

    /// The key is the slot, so two slots sharing a rep range stay separate series — and
    /// their picker labels have to tell them apart even inside one routine.
    ///
    /// Both slots sit at the **same** `order`, which is what the reporter's history holds
    /// and what ticket 03's "· #\(order + 1)" suffix could not disambiguate: the
    /// tiebreaker collided along with the label, and the menu listed two rows reading
    /// character-for-character the same.
    @Test
    func twoSlotsSharingARepRangeStaySeparateAndStayDistinguishable() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let firstSlot = UUID()
        let secondSlot = UUID()
        let older = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        older.routineName = "Pull"
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 10, true)],
                    to: older, context: context, order: 0, routineExerciseId: firstSlot,
                    targetRepMin: 8, targetRepMax: 12)
        let newer = makeEmptySession(startTime: Date(timeIntervalSince1970: 100_000), context: context)
        newer.routineName = "Pull"
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(12, 10, true)],
                    to: newer, context: context, order: 0, routineExerciseId: secondSlot,
                    targetRepMin: 8, targetRepMax: 12)
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: sessions, liveExercises: live,
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: .usage(.routineSlot(secondSlot))
        )

        #expect(snapshot.availableUsages.count == 2)
        #expect(snapshot.data.dataPoints.map(\.maxWeight) == [12])

        // Same routine, same rep range, same position in the workout: only the
        // last-trained date can tell the two entries apart.
        let items = ExerciseUsageLabeling.pickerItems(for: snapshot.availableUsages)
        #expect(items.count == 2)
        #expect(Set(items.map(\.label)).count == 2)
        #expect(items.allSatisfy { $0.label.hasPrefix(snapshot.availableUsages[0].usage.displayLabel) })
    }

    /// The reporter's mixed slot: one routine slot carrying **two rows of the same
    /// workout** — 20 kg heavy and 13 kg light. Keyed on the slot alone they land in one
    /// series, where the per-session `max` collapses them back into the reported sawtooth.
    ///
    /// The rows are inserted light-first while the user performed heavy first, so nothing
    /// here can pass by inheriting `workoutExercisesList`'s order.
    @Test
    func twoRowsOfOneSlotInOneSessionSplitIntoTwoSeries() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let mixedSlot = UUID()
        for day in 1...2 {
            let session = makeEmptySession(
                startTime: Date(timeIntervalSince1970: Double(day) * 1_000),
                context: context
            )
            session.routineName = "Pull"
            // Inserted light-first, performed heavy-first (order 0).
            addExercise(named: exercise.name, exerciseId: exercise.id,
                        sets: [(Double(12 + day), 12, true)],
                        to: session, context: context, order: 1, routineExerciseId: mixedSlot,
                        targetRepMin: 8, targetRepMax: 12)
            addExercise(named: exercise.name, exerciseId: exercise.id,
                        sets: [(Double(19 + day), 5, true)],
                        to: session, context: context, order: 0, routineExerciseId: mixedSlot,
                        targetRepMin: 4, targetRepMax: 6)
        }
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        func snapshot(_ selection: ExerciseUsageSelection?) -> ExerciseProgressSnapshot {
            ExerciseProgressAggregator.buildSnapshot(
                sessions: sessions, liveExercises: live,
                exerciseName: exercise.name, exerciseId: exercise.id,
                startDate: .distantPast, recentSessionLimit: 8,
                requestedUsage: selection
            )
        }

        let heavyKey = ExerciseUsage.Key(slot: .routineSlot(mixedSlot), occurrence: 0)
        let lightKey = ExerciseUsage.Key(slot: .routineSlot(mixedSlot), occurrence: 1)

        // One slot, two usages — described by the row each of them actually is.
        let options = snapshot(nil).availableUsages
        #expect(options.map(\.key) == [heavyKey, lightKey])
        #expect(options.map { $0.usage.repRangeText } == ["4–6", "8–12"])

        // Two clean progressions instead of one collapsed `max`.
        #expect(snapshot(.usage(heavyKey)).data.dataPoints.map(\.maxWeight) == [20, 21])
        #expect(snapshot(.usage(lightKey)).data.dataPoints.map(\.maxWeight) == [13, 14])
        // Combined is unchanged: the session max, as before the picker existed.
        #expect(snapshot(.combined).data.dataPoints.map(\.maxWeight) == [20, 21])

        // The recent-sets list filters by the same key, so the two panels agree.
        let lightCards = snapshot(.usage(lightKey)).recentUsages
        #expect(lightCards.count == 2)
        #expect(lightCards.allSatisfy { $0.usage.key == lightKey })
        #expect(lightCards.map { $0.bestSet?.weight } == [14, 13])
    }

    /// A usage is described by its most recent row, chosen by an explicit comparison —
    /// so two loads of the same unchanged history produce identical labels. The
    /// last-write-wins version read `8–12` on one load and `4–6` on the next.
    @Test
    func theDescriptorIsTheMostRecentRowAndIsStableAcrossLoads() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let slot = UUID()
        // The user later changed this slot's rep-range goal from 8–12 to 4–6.
        let older = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        older.routineName = "Pull"
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: older, context: context, order: 0, routineExerciseId: slot,
                    targetRepMin: 8, targetRepMax: 12)
        let newer = makeEmptySession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        newer.routineName = "Pull"
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: newer, context: context, order: 0, routineExerciseId: slot,
                    targetRepMin: 4, targetRepMax: 6)
        // A second slot, so the picker is not resolved away as a single usage.
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(30, 8, true)],
                    to: newer, context: context, order: 1, routineExerciseId: UUID(),
                    targetRepMin: 8, targetRepMax: 12)
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        func options() -> [ExerciseUsageOption] {
            ExerciseProgressAggregator.buildSnapshot(
                sessions: sessions, liveExercises: live,
                exerciseName: exercise.name, exerciseId: exercise.id,
                startDate: .distantPast, recentSessionLimit: 8
            ).availableUsages
        }

        let first = options()
        #expect(first.first { $0.slot == .routineSlot(slot) }?.usage.repRangeText == "4–6")
        // Same data, loaded again: identical options and identical labels.
        #expect(options() == first)
        #expect(
            ExerciseUsageLabeling.pickerItems(for: options())
                == ExerciseUsageLabeling.pickerItems(for: first)
        )
    }

    /// Two sessions can share a `startTime` to the last bit — HealthKit recovery and watch
    /// ingestion both take it from outside the app — and `sorted(by:)` is not stable, so
    /// the descriptor may not depend on which of them the sort happened to visit last.
    @Test
    func sessionsSharingAStartTimeStillProduceAStableDescriptor() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let slot = UUID()
        let shared = Date(timeIntervalSince1970: 2_000)
        let first = makeEmptySession(startTime: shared, context: context)
        first.routineName = "Pull"
        let firstRow = addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                                   to: first, context: context, order: 0, routineExerciseId: slot,
                                   targetRepMin: 8, targetRepMax: 12)
        let second = makeEmptySession(startTime: shared, context: context)
        second.routineName = "Pull"
        let secondRow = addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                                    to: second, context: context, order: 0, routineExerciseId: slot,
                                    targetRepMin: 4, targetRepMax: 6)
        // A second slot, so the picker is not resolved away as a single usage.
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(30, 8, true)],
                    to: second, context: context, order: 1, routineExerciseId: UUID())
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: sessions, liveExercises: live,
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8
        )

        // Dates and orders tie, so the row id decides — a total order, and the same one
        // on every load rather than whichever row arrived last.
        let expected = firstRow.id.uuidString > secondRow.id.uuidString ? "8–12" : "4–6"
        #expect(snapshot.availableUsages.first { $0.slot == .routineSlot(slot) }?.usage.repRangeText == expected)
    }

    /// Ad-hoc exercises and pre-`routineExerciseId` history are their own bucket: they
    /// are offered as a usage, and they appear in no other one.
    @Test
    func rowsWithNoSlotAreTheirOwnSelectableUsage() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let slot = UUID()
        let legacy = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(16, 10, true)],
                    to: legacy, context: context, order: 0)
        let current = makeEmptySession(startTime: Date(timeIntervalSince1970: 2_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: current, context: context, order: 0, routineExerciseId: slot)
        try context.save()
        let sessions = try fetchSessions(context)
        let live = try context.fetch(FetchDescriptor<Exercise>())

        func snapshot(_ selection: ExerciseUsageSelection) -> ExerciseProgressSnapshot {
            ExerciseProgressAggregator.buildSnapshot(
                sessions: sessions, liveExercises: live,
                exerciseName: exercise.name, exerciseId: exercise.id,
                startDate: .distantPast, recentSessionLimit: 8,
                requestedUsage: selection
            )
        }

        let unattributed = snapshot(.usage(.unattributed))
        #expect(unattributed.availableUsages.map(\.slot).contains(.unattributed))
        #expect(unattributed.data.dataPoints.map(\.maxWeight) == [16])
        #expect(unattributed.recentUsages.allSatisfy { $0.usage.slot == .unattributed })

        // …and the real slot's series does not quietly absorb them.
        #expect(snapshot(.usage(.routineSlot(slot))).data.dataPoints.map(\.maxWeight) == [20])
    }

    /// History that carries no slot ids at all — every row legacy — is one usage, not
    /// zero: the chart must still draw, and it must draw everything.
    @Test
    func historyWithNoSlotIdsAtAllStillCharts() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        for day in 1...3 {
            let session = makeEmptySession(
                startTime: Date(timeIntervalSince1970: Double(day) * 1_000),
                context: context
            )
            addExercise(named: exercise.name, exerciseId: exercise.id,
                        sets: [(Double(10 + day), 10, true)],
                        to: session, context: context, order: 0)
        }
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: nil
        )

        #expect(snapshot.availableUsages.map(\.slot) == [.unattributed])
        #expect(snapshot.selectedUsage == .combined)
        #expect(snapshot.data.dataPoints.map(\.maxWeight) == [11, 12, 13])
        #expect(snapshot.recentUsages.count == 3)
    }

    /// Narrowing the timeframe can leave the selected usage outside the window. The
    /// picker is all-time, so the usage stays listed and stays selected — the chart draws
    /// its empty state, which one tap on a wider range recovers from. Ticket 03 swapped
    /// the selection out instead, and the menu reshuffled on every timeframe tap.
    @Test
    func aSelectedUsageOutsideTheWindowIsKeptAndRendersEmpty() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let oldSlot = UUID()
        let recentSlotA = UUID()
        let recentSlotB = UUID()
        let old = makeEmptySession(startTime: Date(timeIntervalSince1970: 1_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(20, 5, true)],
                    to: old, context: context, order: 0, routineExerciseId: oldSlot)
        let recent = makeEmptySession(startTime: Date(timeIntervalSince1970: 9_000), context: context)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(24, 5, true)],
                    to: recent, context: context, order: 0, routineExerciseId: recentSlotA)
        addExercise(named: exercise.name, exerciseId: exercise.id, sets: [(14, 12, true)],
                    to: recent, context: context, order: 1, routineExerciseId: recentSlotB)
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: Date(timeIntervalSince1970: 5_000), recentSessionLimit: 8,
            requestedUsage: .usage(.routineSlot(oldSlot))
        )

        // Every usage in history is offered, including the one the window excludes.
        #expect(snapshot.availableUsages.map(\.slot) == [
            .routineSlot(recentSlotA), .routineSlot(recentSlotB), .routineSlot(oldSlot)
        ])
        // The choice is kept, and the chart is simply empty for this window.
        #expect(snapshot.selectedUsage == .usage(.routineSlot(oldSlot)))
        #expect(snapshot.data.dataPoints.isEmpty)

        // Widening the window brings the data back without the menu having moved.
        let widened = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: exercise.name, exerciseId: exercise.id,
            startDate: .distantPast, recentSessionLimit: 8,
            requestedUsage: .usage(.routineSlot(oldSlot))
        )
        #expect(widened.availableUsages == snapshot.availableUsages)
        #expect(widened.data.dataPoints.map(\.maxWeight) == [20])
    }

    /// With a usage selected the cap still counts sessions, so the list reaches back
    /// `limit` workouts **of that usage** rather than showing what survives a filter.
    @Test
    func theRecentListFiltersToTheSelectedUsageAndKeepsItsSessionCap() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Biceps Curls")
        context.insert(exercise)

        let heavySlot = UUID()
        let lightSlot = UUID()
        // Six workouts, alternating between the two usages.
        for day in 1...6 {
            let session = makeEmptySession(
                startTime: Date(timeIntervalSince1970: Double(day) * 1_000),
                context: context
            )
            addExercise(named: exercise.name, exerciseId: exercise.id,
                        sets: [(day.isMultiple(of: 2) ? 14 : 20, 8, true)],
                        to: session, context: context, order: 0,
                        routineExerciseId: day.isMultiple(of: 2) ? lightSlot : heavySlot)
        }
        try context.save()

        let heavy = ExerciseProgressAggregator.buildRecentUsages(
            sessions: try fetchSessions(context),
            exerciseName: exercise.name, exerciseId: exercise.id,
            nameIsUnique: true, loadBehavior: .resistance, limit: 2,
            usageSelection: .usage(.routineSlot(heavySlot))
        )

        // Two sessions deep into the heavy usage — days 5 and 3, not days 6 and 5.
        #expect(heavy.count == 2)
        #expect(heavy.allSatisfy { $0.usage.slot == .routineSlot(heavySlot) })
        #expect(heavy.map(\.date) == [
            Date(timeIntervalSince1970: 5_000),
            Date(timeIntervalSince1970: 3_000)
        ])
    }

    /// A slot-less row carries a rep-range goal like any other, so the bucket used to be
    /// labelled exactly like a routine slot — which is how the reporter's picker came to
    /// offer `4–6 Wdh. · Pull` twice, one of them being this bucket. The marker leads.
    @Test
    func anUnattributedUsageWithARepGoalIsStillMarkedUnassigned() {
        let unattributed = ExerciseUsage(
            key: .unattributed,
            targetRepMin: 4,
            targetRepMax: 6,
            routineName: "Pull"
        )
        let slot = ExerciseUsage(
            key: .routineSlot(UUID()),
            targetRepMin: 4,
            targetRepMax: 6,
            routineName: "Pull"
        )

        #expect(unattributed.displayLabel != slot.displayLabel)
        #expect(unattributed.displayLabel.hasPrefix("history.exercise.usage.unassigned".localized))
        // The goal is still named — it is what tells two slot-less usages of one workout apart.
        #expect(unattributed.displayLabel.contains(slot.displayLabel))
        // Unchanged for a bucket with no goal at all.
        #expect(
            ExerciseUsage(key: .unattributed, targetRepMin: nil, targetRepMax: nil, routineName: "Pull")
                .displayLabel == "history.exercise.usage.unassigned".localized + " · Pull"
        )
    }

    /// Labels only carry a suffix when they would otherwise collide.
    @Test
    func pickerLabelsAreOnlyDisambiguatedWhenTheyCollide() {
        let distinct = [
            option(repMin: 4, repMax: 6, lastPerformed: Date(timeIntervalSince1970: 2_000)),
            option(repMin: 8, repMax: 12, lastPerformed: Date(timeIntervalSince1970: 1_000))
        ]

        let items = ExerciseUsageLabeling.pickerItems(for: distinct)
        #expect(Set(items.map(\.label)).count == 2)
        #expect(items.map(\.label) == distinct.map { $0.usage.displayLabel })
    }

    /// Two entries the date cannot separate either — same label, same last workout — fall
    /// back to their position in the menu, the one suffix guaranteed unique. `slotOrder`
    /// was not: the reporter's two colliding slots both sat at position 1.
    @Test
    func collidingLabelsWithTheSameDateFallBackToAUniqueMenuIndex() {
        let sameDay = Date(timeIntervalSince1970: 2_000)
        let colliding = [
            option(repMin: 8, repMax: 12, lastPerformed: sameDay, order: 1),
            option(repMin: 8, repMax: 12, lastPerformed: sameDay, order: 1)
        ]

        let items = ExerciseUsageLabeling.pickerItems(for: colliding)
        #expect(Set(items.map(\.label)).count == 2)
        #expect(items.allSatisfy { $0.label.contains("#") })
    }

    /// Colliding labels are separated by the date they were last trained — which is what
    /// tells the user which entry their live routine still holds.
    @Test
    func collidingLabelsCarryTheLastTrainedDate() {
        let items = ExerciseUsageLabeling.pickerItems(for: [
            option(repMin: 8, repMax: 12, lastPerformed: Date(timeIntervalSince1970: 2_000)),
            option(repMin: 8, repMax: 12, lastPerformed: Date(timeIntervalSince1970: 100_000))
        ])

        #expect(Set(items.map(\.label)).count == 2)
        #expect(items.allSatisfy { !$0.label.contains("#") })
        #expect(items.allSatisfy { $0.label.count > "8–12 · Pull".count })
    }

    @Test
    func loadBehaviorResolvesByIdThenNameAndFallsBackToResistance() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let assisted = Exercise(name: "Assisted Pull-Up")
        assisted.loadBehavior = .counterweightAssistance
        context.insert(assisted)
        try context.save()

        let live = try context.fetch(FetchDescriptor<Exercise>())

        #expect(
            ExerciseProgressAggregator.loadBehavior(
                exerciseId: assisted.id, exerciseName: "irrelevant", in: live
            ) == .counterweightAssistance
        )
        #expect(
            ExerciseProgressAggregator.loadBehavior(
                exerciseId: nil, exerciseName: "assisted pull-up", in: live
            ) == .counterweightAssistance
        )
        // Deleted from the library — the chart still renders, as plain resistance.
        #expect(
            ExerciseProgressAggregator.loadBehavior(
                exerciseId: UUID(), exerciseName: "Gone", in: live
            ) == .resistance
        )
    }

    // MARK: - Fixtures

    private func option(
        repMin: Int,
        repMax: Int,
        lastPerformed: Date,
        order: Int = 0
    ) -> ExerciseUsageOption {
        ExerciseUsageOption(
            usage: ExerciseUsage(
                key: .routineSlot(UUID()),
                targetRepMin: repMin,
                targetRepMax: repMax,
                routineName: "Pull"
            ),
            lastPerformed: lastPerformed,
            lastPerformedOrder: order
        )
    }

    private func fetchSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endTime != nil })
        )
    }

    private func makeEmptySession(startTime: Date, context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        context.insert(session)
        return session
    }

    @discardableResult
    private func makeSession(
        startTime: Date,
        sets: [(weight: Double, reps: Int, completed: Bool)],
        exercise: Exercise,
        context: ModelContext
    ) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = startTime
        session.endTime = startTime.addingTimeInterval(600)
        context.insert(session)
        addExercise(
            named: exercise.name,
            exerciseId: exercise.id,
            sets: sets.map { ($0.weight, $0.reps, $0.completed) },
            to: session,
            context: context
        )
        return session
    }

    @discardableResult
    private func addExercise(
        named name: String,
        exerciseId: UUID?,
        sets: [(Double, Int, Bool)],
        to session: WorkoutSession,
        context: ModelContext,
        order: Int = 0,
        routineExerciseId: UUID? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        loadBehavior: ExerciseLoadBehavior = .resistance
    ) -> WorkoutExercise {
        let workoutExercise = WorkoutExercise(
            exerciseName: name,
            muscleGroups: ["Chest"],
            order: order,
            exerciseId: exerciseId,
            routineExerciseId: routineExerciseId,
            loadBehavior: loadBehavior
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
        return workoutExercise
    }
}
