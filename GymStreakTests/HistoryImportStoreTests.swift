//
//  HistoryImportStoreTests.swift
//  GymStreakTests
//
//  The import's write side against a real (in-memory) store: what lands in history,
//  library matching, custom-exercise creation, units and idempotency
//  (docs/history-import.md §3–§4).
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct HistoryImportStoreTests {

    private static let csv = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
    2024-03-05 18:01:12,Push Day,1h,bench  press,1,100,5,0,0,
    2024-03-05 18:01:12,Push Day,1h,bench  press,2,100,4,0,0,
    2024-03-05 18:01:12,Push Day,1h,Cable Fly (Cable),1,20,12,0,0,
    2024-03-05 18:01:12,Push Day,1h,Running,1,0,0,2000,600,
    2024-03-08 18:00:00,Push Day,50m,Bench Press,1,102.5,5,0,0,
    """

    @Test("A Strong file lands in history as completed, routine-less sessions")
    func importsIntoHistory() async throws {
        let (container, provider, bench) = try makeStore()
        let url = try writeFile(Self.csv)

        let preview = try await provider.prepareStrongImport(from: url)
        #expect(preview.workoutCount == 2)
        #expect(preview.matchedExerciseCount == 1)
        #expect(preview.newExerciseNames == ["Cable Fly (Cable)"])
        #expect(preview.alreadyImportedCount == 0)
        #expect(preview.file.skippedCardioSetCount == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()) == 0, "preview writes nothing")

        let result = try await provider.importHistory(preview.file, weightUnit: .kilograms) { _ in }
        #expect(result == HistoryImportResult(
            importedWorkoutCount: 2, skippedDuplicateCount: 0, createdExerciseCount: 1, skippedCardioSetCount: 1
        ))

        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime)]))
        #expect(sessions.count == 2)
        let first = try #require(sessions.first)
        #expect(first.routine == nil)
        #expect(first.routineName == "Push Day")
        #expect(first.endTime == first.startTime.addingTimeInterval(3_600))
        #expect(first.healthKitWorkoutId == nil)

        let exercises = first.workoutExercisesList.sorted { $0.order < $1.order }
        #expect(exercises.map(\.exerciseName) == ["Bench Press", "Cable Fly (Cable)"])
        #expect(exercises[0].exerciseId == bench, "a matched name continues the library exercise's chart")
        #expect(exercises[0].setsList.allSatisfy { $0.isCompleted })
        #expect(exercises[0].setsList.sorted { $0.order < $1.order }.map(\.actualReps) == [5, 4])

        let created = try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Cable Fly (Cable)" })
        #expect(created.seedKey.isEmpty, "created like a user exercise, not a seeded one")
        #expect(created.equipmentType == .cable)
        #expect(exercises[1].exerciseId == created.id)
    }

    @Test("Re-importing the same file creates nothing")
    func reimportIsIdempotent() async throws {
        let (container, provider, _) = try makeStore()
        let url = try writeFile(Self.csv)
        let first = try await provider.prepareStrongImport(from: url)
        _ = try await provider.importHistory(first.file, weightUnit: .kilograms) { _ in }

        let second = try await provider.prepareStrongImport(from: url)
        #expect(second.alreadyImportedCount == 2)
        #expect(second.newExerciseNames.isEmpty)
        let result = try await provider.importHistory(second.file, weightUnit: .kilograms) { _ in }

        #expect(result.importedWorkoutCount == 0)
        #expect(result.skippedDuplicateCount == 2)
        #expect(result.createdExerciseCount == 0)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 2)
    }

    @Test("Pound files are stored as canonical kilograms")
    func poundsAreConverted() async throws {
        let (container, provider, _) = try makeStore()
        let preview = try await provider.prepareStrongImport(from: try writeFile(Self.csv))
        _ = try await provider.importHistory(preview.file, weightUnit: .pounds) { _ in }

        let sets = try ModelContext(container).fetch(FetchDescriptor<WorkoutSet>())
        let heaviest = try #require(sets.map(\.actualWeight).max())
        #expect(abs(heaviest - WeightUnit.pounds.kilograms(fromDisplay: 102.5)) < 0.0001)
    }

    @Test("A non-Strong file is rejected and writes nothing")
    func foreignFileWritesNothing() async throws {
        let (container, provider, _) = try makeStore()
        let url = try writeFile("name,weight\nBench,60")

        await #expect(throws: HistoryImportError.notAStrongExport) {
            _ = try await provider.prepareStrongImport(from: url)
        }
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    // MARK: - Helpers

    private func makeStore() throws -> (ModelContainer, any HistoryImporting, UUID) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let bench = Exercise(name: "Bench Press", equipmentType: .barbell)
        context.insert(bench)
        try context.save()
        return (container, SwiftDataHistoryImportProvider(modelContainer: container, gate: .unshared()), bench.id)
    }

    private func writeFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("strong-\(UUID().uuidString).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
