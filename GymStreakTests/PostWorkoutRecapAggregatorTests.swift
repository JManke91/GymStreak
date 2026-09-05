//
//  PostWorkoutRecapAggregatorTests.swift
//  GymStreakTests
//
//  Measured on device, German, 2026-08-30: a session whose own summary read `8/20 (40%)`
//  was recapped as "mit einem Gesamtvolumen von 1980,0 kg und 20 Sätzen". The volume was
//  right — it has always summed completed sets — and the set count was the *planned* one,
//  so one generated sentence stated two figures that describe different sessions.
//
//  The recap now reads both from the same `WorkoutSession.aggregates` pass. These tests
//  pin the figure the prompt carries; whether the model copies it is a device check.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct PostWorkoutRecapAggregatorTests {

    @Test("The recap states completed sets, never the planned ones")
    func recapCountsCompletedSetsOnly() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        // 3 of 5 sets finished — the shape of the 8/20 session that produced the wrong copy.
        addExercise(to: session, sets: [(100, 5, true), (100, 5, true), (100, 5, false)], context: context)
        addExercise(to: session, sets: [(50, 10, true), (50, 10, false)], context: context)
        try context.save()

        let input = PostWorkoutRecapAggregator().buildInput(
            session: session,
            locale: Locale(identifier: "de_DE"),
            modelContext: context
        )

        #expect(input.completedSets == 3)
        #expect(session.totalSetsCount == 5, "fixture sanity: the planned count differs from the completed one")
    }

    /// The two figures sit in one generated sentence, so they have to describe the same
    /// sets: volume already excluded the unfinished ones.
    @Test("The set count and the volume describe the same sets")
    func setCountAndVolumeAgree() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        addExercise(to: session, sets: [(100, 5, true), (100, 5, false)], context: context)
        try context.save()

        let input = PostWorkoutRecapAggregator().buildInput(
            session: session,
            locale: Locale(identifier: "de_DE"),
            modelContext: context
        )

        #expect(input.completedSets == 1)
        #expect(input.workoutVolumeKg == 500)   // the unfinished set contributes to neither
    }

    @Test("The prompt line the model reads says the count is a completed one")
    func promptLabelsTheCountAsCompleted() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let session = makeSession(context: context)
        addExercise(to: session, sets: [(100, 5, true), (100, 5, false)], context: context)
        try context.save()

        let prompt = PostWorkoutRecapAggregator().buildInput(
            session: session,
            locale: Locale(identifier: "de_DE"),
            modelContext: context
        ).toPromptText(in: .kilograms)

        #expect(prompt.contains("Completed sets: 1"))
        #expect(!prompt.contains("Total sets"))
    }

    // MARK: - Fixtures

    private func makeSession(context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.routineName = "Push"
        session.endTime = session.startTime.addingTimeInterval(3_600)
        context.insert(session)
        return session
    }

    private func addExercise(
        to session: WorkoutSession,
        sets: [(weight: Double, reps: Int, done: Bool)],
        context: ModelContext
    ) {
        let exercise = WorkoutExercise(
            exerciseName: "Bench Press",
            muscleGroups: ["chest"],
            order: session.workoutExercisesList.count,
            exerciseId: UUID()
        )
        exercise.workoutSession = session
        context.insert(exercise)

        for (index, spec) in sets.enumerated() {
            let set = WorkoutSet(
                plannedReps: spec.reps,
                actualReps: spec.reps,
                plannedWeight: spec.weight,
                actualWeight: spec.weight,
                restTime: 60,
                order: index
            )
            set.isCompleted = spec.done
            set.workoutExercise = exercise
            context.insert(set)
        }
    }
}
