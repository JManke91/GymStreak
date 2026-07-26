//
//  SwiftDataHistorySnapshotStoreTests.swift
//  GymStreakTests
//
//  Integration coverage for History's actor-owned read boundary.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct SwiftDataHistorySnapshotStoreTests {
    @Test
    func largeSnapshotBuildKeepsMainActorResponsive() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        try seedHistory(sessionCount: 240, context: context)

        let provider = SwiftDataHistorySnapshotProvider(modelContainer: container)
        let heartbeat = MainActorHeartbeat(interval: .milliseconds(10))
        let heartbeatTask = Task { await heartbeat.run() }
        await Task.yield()

        let snapshot = try await provider.fetchTrainingSnapshot(referenceDate: Date())

        heartbeatTask.cancel()
        await heartbeatTask.value

        #expect(snapshot.sessionCount == 240)
        #expect(
            heartbeat.sampleCount >= 1,
            "the main actor should run while the model actor is building the snapshot"
        )
        #expect(
            heartbeat.maximumDelay < .milliseconds(100),
            "History snapshot work delayed MainActor by \(heartbeat.maximumDelay)"
        )
    }

    private func seedHistory(sessionCount: Int, context: ModelContext) throws {
        let referenceDate = Date()

        for sessionIndex in 0..<sessionCount {
            let startTime = referenceDate.addingTimeInterval(-Double(sessionIndex) * 86_400)
            let session = WorkoutSession(routine: nil)
            session.routineName = "Stress \(sessionIndex % 3)"
            session.startTime = startTime
            session.endTime = startTime.addingTimeInterval(3_600)
            context.insert(session)

            for exerciseIndex in 0..<5 {
                let workoutExercise = WorkoutExercise(
                    exerciseName: "Exercise \(exerciseIndex)",
                    muscleGroups: ["General"],
                    order: exerciseIndex,
                    exerciseId: nil
                )
                workoutExercise.workoutSession = session
                context.insert(workoutExercise)

                for setIndex in 0..<4 {
                    let set = WorkoutSet(
                        plannedReps: 10,
                        actualReps: 10,
                        plannedWeight: Double(40 + exerciseIndex),
                        actualWeight: Double(40 + exerciseIndex),
                        restTime: 60,
                        order: setIndex
                    )
                    set.isCompleted = true
                    set.workoutExercise = workoutExercise
                    context.insert(set)
                    workoutExercise.sets?.append(set)
                }

                session.workoutExercises?.append(workoutExercise)
            }
        }

        try context.save()
    }
}

@MainActor
private final class MainActorHeartbeat {
    private let clock = ContinuousClock()
    private let interval: Duration

    private(set) var sampleCount = 0
    private(set) var maximumDelay: Duration = .zero

    init(interval: Duration) {
        self.interval = interval
    }

    func run() async {
        while !Task.isCancelled {
            let expectedWake = clock.now.advanced(by: interval)
            do {
                try await clock.sleep(until: expectedWake)
            } catch {
                return
            }

            let delay = expectedWake.duration(to: clock.now)
            sampleCount += 1
            if delay > maximumDelay {
                maximumDelay = delay
            }
        }
    }
}
