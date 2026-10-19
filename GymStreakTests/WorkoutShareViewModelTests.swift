//
//  WorkoutShareViewModelTests.swift
//  GymStreakTests
//
//  `WorkoutShareViewModel`: History's prepare path that reuses already-loaded PRs, and the
//  preview's "Save" state across chip changes. See docs/workout-sharing.md.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct WorkoutShareViewModelTests {

    @Test
    func knownRecordsAreUsedWithoutWalkingHistory() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let (session, bench) = makeSession(context: context)
        let bests = CountingPersonalBests()
        let viewModel = WorkoutShareViewModel(personalBests: bests, photoLibrary: GatedPhotoLibrary(), campaign: "test")

        let record = PersonalRecordService.PRDetail(
            exerciseKey: bench.stableKey, workoutExerciseId: bench.id, setId: UUID(),
            weight: 100, reps: 5, estimatedOneRepMax: 116, previousBest: 110
        )
        await viewModel.prepare(session: session, weightUnit: .kilograms, knownRecords: [bench.id: record])

        #expect(await bests.callCount == 0)
        #expect(viewModel.card?.records.count == 1)
        #expect(viewModel.entrySubtitle == "share.entry.subtitle_pr_one".localized)
    }

    @Test
    func chipChangedDuringSaveDoesNotMarkTheNewCardSaved() async throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let (session, _) = makeSession(context: context)
        let photos = GatedPhotoLibrary()
        let viewModel = WorkoutShareViewModel(personalBests: CountingPersonalBests(), photoLibrary: photos, campaign: "test")
        await viewModel.prepare(session: session, weightUnit: .kilograms, knownRecords: [:])

        let save = Task { await viewModel.saveImage() }
        while await !photos.isWaiting { await Task.yield() }
        #expect(viewModel.saveState == .saving)
        viewModel.layers.stats.toggle()
        #expect(viewModel.saveState == .saving)
        await photos.release()
        await save.value
        #expect(viewModel.saveState == .idle)

        let second = Task { await viewModel.saveImage() }
        while await !photos.isWaiting { await Task.yield() }
        await photos.release()
        await second.value
        #expect(viewModel.saveState == .saved)
        viewModel.layers.stats.toggle()
        #expect(viewModel.saveState == .idle)
    }

    private func makeSession(context: ModelContext) -> (WorkoutSession, WorkoutExercise) {
        let routine = Routine(name: "Push")
        context.insert(routine)
        let session = WorkoutSession(routine: routine)
        session.startTime = Date(timeIntervalSince1970: 2_000)
        session.endTime = Date(timeIntervalSince1970: 4_000)
        context.insert(session)
        let bench = WorkoutExercise(exerciseName: "Bench Press", muscleGroups: ["chest"], order: 0, exerciseId: UUID())
        bench.workoutSession = session
        context.insert(bench)
        let set = WorkoutSet(plannedReps: 5, actualReps: 5, plannedWeight: 100, actualWeight: 100, restTime: 60, order: 0)
        set.isCompleted = true
        set.workoutExercise = bench
        context.insert(set)
        return (session, bench)
    }
}

private actor CountingPersonalBests: PersonalBestsProviding {
    private(set) var callCount = 0
    func fetchPersonalBests(before date: Date, excludingSessionID: UUID) async throws -> [String: Double] {
        callCount += 1
        return [:]
    }
}

/// Holds each save until the test releases it.
private actor GatedPhotoLibrary: PhotoLibrarySaving {
    private var pending: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { pending != nil }

    func savePNG(_ data: Data) async throws {
        await withCheckedContinuation { pending = $0 }
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}
