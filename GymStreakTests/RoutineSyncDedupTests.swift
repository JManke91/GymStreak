//
//  RoutineSyncDedupTests.swift
//  GymStreakTests
//
//  The routine-sync duplicate suppression in WatchConnectivityManager compares
//  encoded payload bytes — it is only sound if identical content always
//  encodes to identical bytes and meaningful changes (values, routine order)
//  never collide. These tests pin that contract.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct RoutineSyncDedupTests {

    private func makeRoutine(id: UUID = UUID(), name: String = "Push Day", weight: Double = 60) -> WatchRoutine {
        WatchRoutine(
            id: id,
            name: name,
            exercises: [
                WatchExercise(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "Bench Press",
                    muscleGroup: "Chest",
                    sets: [
                        WatchSet(
                            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                            reps: 8,
                            weight: weight,
                            restTime: 90
                        )
                    ],
                    order: 0,
                    supersetId: nil,
                    supersetOrder: 0
                )
            ]
        )
    }

    @Test
    func identicalContentEncodesToIdenticalBytes() {
        let id = UUID()
        let first = WatchConnectivityManager.encodeRoutinesPayload([makeRoutine(id: id)])
        let second = WatchConnectivityManager.encodeRoutinesPayload([makeRoutine(id: id)])

        #expect(first != nil)
        #expect(first == second)
    }

    @Test
    func changedValuesProduceDifferentBytes() {
        let id = UUID()
        let before = WatchConnectivityManager.encodeRoutinesPayload([makeRoutine(id: id, weight: 60)])
        let after = WatchConnectivityManager.encodeRoutinesPayload([makeRoutine(id: id, weight: 62.5)])

        #expect(before != after)
    }

    @Test
    func routineOrderIsMeaningful() {
        // Index 0 is the watch's "Up Next" hero, so a reordering must resync.
        let a = makeRoutine(name: "Push Day")
        let b = makeRoutine(name: "Pull Day")
        let forward = WatchConnectivityManager.encodeRoutinesPayload([a, b])
        let reversed = WatchConnectivityManager.encodeRoutinesPayload([b, a])

        #expect(forward != reversed)
    }
}
