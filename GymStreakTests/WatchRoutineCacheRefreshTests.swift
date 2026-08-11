//
//  WatchRoutineCacheRefreshTests.swift
//  GymStreakTests
//
//  `SwiftDataMainContextRoutineCacheRefresher` mirrors an already-committed
//  authoritative snapshot into the app's long-lived main context. It runs right
//  after a watch template transaction commits in a SIBLING context, and it then
//  SAVES that context — which, once the app has been running, is what actually
//  establishes those values in the store (see the type's own documentation and
//  `docs/watch-sync.md`). A field it fails to copy therefore reverts to whatever
//  the main context last held, silently and only on device.
//
//  These tests are FILE-BACKED on purpose: an in-memory store performs no
//  row-version conflict resolution, so this whole bug class passes there.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WatchRoutineCacheRefreshTests {
    /// Seeds one routine whose slot has three sets at 10×60 kg / 120 s, plus an
    /// alternative with its own scheme (swapped exercises write there).
    private func seed(_ context: ModelContext) throws -> Routine {
        let exercise = Exercise(name: "Bench Press")
        let alternativeExercise = Exercise(name: "Dumbbell Press")
        context.insert(exercise)
        context.insert(alternativeExercise)

        let routine = Routine(name: "Push Day")
        let slot = RoutineExercise(exercise: exercise, order: 0)
        slot.routine = routine
        for order in 0..<3 {
            let set = ExerciseSet(reps: 10, weight: 60, restTime: 120, order: order)
            set.routineExercise = slot
            slot.sets?.append(set)
        }

        let alternative = RoutineExerciseAlternative(exercise: alternativeExercise, order: 0)
        alternative.routineExercise = slot
        let alternativeSet = AlternativeExerciseSet(reps: 10, weight: 25, restTime: 120, order: 0)
        alternativeSet.alternative = alternative
        alternative.sets?.append(alternativeSet)
        slot.alternatives?.append(alternative)

        routine.routineExercises?.append(slot)
        context.insert(routine)
        try context.save()
        return routine
    }

    /// The regression itself: the mirror must carry EVERY field `WatchSet`
    /// transports, for primary schemes and alternative schemes alike. Removing
    /// either `cachedSet.restTime = …` in `refreshCache` fails this.
    @Test
    func mirrorCarriesEveryFieldTheSnapshotTransports() throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let mainContext = container.mainContext
        let routine = try seed(mainContext)
        let slot = try #require(routine.routineExercisesList.first)
        let alternative = try #require(slot.alternativesList.first)

        // A snapshot carrying values the main context has never seen.
        let snapshot = [WatchRoutine(
            id: routine.id,
            name: routine.name,
            exercises: [WatchExercise(
                id: slot.id,
                name: "Bench Press",
                muscleGroup: "Chest",
                sets: slot.setsList.map {
                    WatchSet(id: $0.id, reps: 12, weight: 72.5, restTime: 195)
                },
                order: 0,
                supersetId: nil,
                supersetOrder: 0,
                alternatives: [WatchExerciseAlternative(
                    id: alternative.id,
                    exerciseId: alternative.exercise?.id ?? UUID(),
                    name: "Dumbbell Press",
                    muscleGroup: "Chest",
                    sets: alternative.setsList.map {
                        WatchSet(id: $0.id, reps: 8, weight: 30, restTime: 150)
                    },
                    order: 0
                )]
            )]
        )]

        SwiftDataMainContextRoutineCacheRefresher(modelContext: mainContext).refreshCache(from: snapshot)

        let mirrored = routine.routineExercisesList[0].setsList
        #expect(mirrored.allSatisfy { $0.reps == 12 })
        #expect(mirrored.allSatisfy { $0.weight == 72.5 })
        #expect(mirrored.allSatisfy { $0.restTime == 195 })

        let mirroredAlternative = routine.routineExercisesList[0].alternativesList[0].setsList
        #expect(mirroredAlternative.allSatisfy { $0.reps == 8 })
        #expect(mirroredAlternative.allSatisfy { $0.weight == 30 })
        #expect(mirroredAlternative.allSatisfy { $0.restTime == 150 })
    }

    /// The mirror runs against a main context holding pre-transaction values and
    /// then saves it, so it must leave BOTH the store and that context agreeing
    /// with what the sibling committed — never carrying a stale value back.
    @Test
    func mirroringLeavesStoreAndMainContextAgreeingWithTheCommittedValues() throws {
        let (container, cleanUp) = try FileBackedModelContainer.make()
        defer { cleanUp() }
        let mainContext = container.mainContext
        let routine = try seed(mainContext)
        let routineID = routine.id

        // The main context has now loaded these rows — exactly the state it is
        // in when a watch transaction arrives.
        #expect(routine.routineExercisesList[0].setsList.allSatisfy { $0.restTime == 120 })

        // A sibling (isolated) transaction commits the watch's rest change,
        // just as `WatchTemplateTransactionService` does.
        let sibling = ModelContext(container)
        let siblingRoutine = try #require(SwiftDataRoutineRepository(modelContext: sibling).fetch(id: routineID))
        for set in siblingRoutine.routineExercisesList[0].setsList {
            set.restTime = 195
            set.reps = 12
        }
        try sibling.save()

        let snapshot = try SwiftDataAuthoritativeRoutineSnapshotProvider(container: container).fetchSnapshot()
        #expect(snapshot.first?.exercises.first?.sets.allSatisfy { $0.restTime == 195 } == true)
        SwiftDataMainContextRoutineCacheRefresher(modelContext: mainContext).refreshCache(from: snapshot)

        // The app's main context autosaves, so it saves AGAIN after the mirror
        // ran — carrying whatever the mirror left in it.
        mainContext.autosaveEnabled = true
        try mainContext.save()

        let verify = ModelContext(container)
        let committed = try #require(SwiftDataRoutineRepository(modelContext: verify).fetch(id: routineID))
        let sets = committed.routineExercisesList[0].setsList
        #expect(sets.allSatisfy { $0.reps == 12 })
        #expect(sets.allSatisfy { $0.restTime == 195 })
        // What the main context itself believes matters most: it is the context
        // every screen reads, and the one whose next save wins.
        #expect(routine.routineExercisesList[0].setsList.allSatisfy { $0.restTime == 195 })
    }
}
