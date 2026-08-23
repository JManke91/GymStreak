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
            recentSessionLimit: 8
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
