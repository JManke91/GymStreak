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
        let summary = preview.summary(in: nil)
        #expect(summary.workoutCount == 2)
        #expect(summary.matchedExerciseCount == 1)
        #expect(summary.newExerciseNames == ["Cable Fly (Cable)"])
        #expect(summary.alreadyImportedCount == 0)
        #expect(preview.file.skippedCardioSetCount == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()) == 0, "preview writes nothing")

        let result = try await provider.importHistory(preview.file, weightUnit: .kilograms, createsMissingExercises: true) { _ in }
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

    @Test("History-only import leaves the library untouched, and links up by name later")
    func historyOnlyImport() async throws {
        let (container, provider, bench) = try makeStore()
        let preview = try await provider.prepareStrongImport(from: try writeFile(Self.csv))
        let result = try await provider.importHistory(
            preview.file, weightUnit: .kilograms, createsMissingExercises: false
        ) { _ in }

        #expect(result.createdExerciseCount == 0)
        #expect(result.importedWorkoutCount == 2)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1, "no exercise was added")

        let rows = try context.fetch(FetchDescriptor<WorkoutExercise>())
        let fly = try #require(rows.first { $0.exerciseName == "Cable Fly (Cable)" })
        #expect(fly.exerciseId == nil, "a history-only row carries its name, not a library link")
        #expect(fly.setsList.count == 1)
        #expect(rows.filter { $0.exerciseName == "Bench Press" }.allSatisfy { $0.exerciseId == bench },
                "matched names link to the library in both modes")

        // Invisible in Fortschritt until an exercise of that name exists, then picked up.
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let before = FortschrittAggregator.build(sessions: sessions, liveExercises: try context.fetch(FetchDescriptor<Exercise>()))
        #expect(!before.contains { $0.name == "Cable Fly (Cable)" })
        context.insert(Exercise(name: "Cable Fly (Cable)", equipmentType: .cable))
        try context.save()
        let after = FortschrittAggregator.build(sessions: sessions, liveExercises: try context.fetch(FetchDescriptor<Exercise>()))
        #expect(after.contains { $0.name == "Cable Fly (Cable)" })
    }

    /// PRs and AI recaps key by `stableKey` with no name fallback, so a name-only row must
    /// be *linked* once a same-named exercise is created — not just shown by name in charts.
    @Test("Creating an exercise links the history-only rows of its name")
    func creatingExerciseLinksNameOnlyRows() async throws {
        let (container, provider, _) = try makeStore()
        let preview = try await provider.prepareStrongImport(from: try writeFile(Self.csv))
        _ = try await provider.importHistory(
            preview.file, weightUnit: .kilograms, createsMissingExercises: false
        ) { _ in }

        let context = ModelContext(container)
        let library = ExercisesViewModel(
            exerciseRepository: SwiftDataExerciseRepository(modelContext: context),
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            catalogSync: ImportTestCatalogSync(),
            legacyHistoryAttribution: SwiftDataLegacyHistoryAttributionProvider(
                modelContainer: container, gate: .unshared()
            )
        )
        let fly = try #require(library.addExercise(name: "cable fly (cable)", muscleGroups: ["Chest"]))

        var linkedId: UUID?
        for _ in 0..<100 where linkedId == nil {
            try await Task.sleep(for: .milliseconds(20))
            linkedId = try ModelContext(container).fetch(FetchDescriptor<WorkoutExercise>())
                .first { $0.exerciseName == "Cable Fly (Cable)" }?.exerciseId
        }
        #expect(linkedId == fly.id)
    }

    @Test("A later import that creates an exercise links the earlier history-only rows")
    func laterCreatingImportLinksNameOnlyRows() async throws {
        let (container, provider, _) = try makeStore()
        let historyOnly = try await provider.prepareStrongImport(from: try writeFile(Self.csv))
        _ = try await provider.importHistory(
            historyOnly.file, weightUnit: .kilograms, createsMissingExercises: false
        ) { _ in }

        let newer = try await provider.prepareStrongImport(from: try writeFile("""
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
        2024-04-01 18:00:00,Push Day,1h,Cable Fly (Cable),1,22.5,12,0,0,
        """))
        let result = try await provider.importHistory(
            newer.file, weightUnit: .kilograms, createsMissingExercises: true
        ) { _ in }
        #expect(result.createdExerciseCount == 1)

        let context = ModelContext(container)
        let created = try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Cable Fly (Cable)" })
        let flyRows = try context.fetch(FetchDescriptor<WorkoutExercise>()).filter { $0.exerciseName == "Cable Fly (Cable)" }
        #expect(flyRows.count == 2)
        #expect(flyRows.allSatisfy { $0.exerciseId == created.id }, "old and new rows share one history")
    }

    @Test("Re-importing the same file creates nothing")
    func reimportIsIdempotent() async throws {
        let (container, provider, _) = try makeStore()
        let url = try writeFile(Self.csv)
        let first = try await provider.prepareStrongImport(from: url)
        _ = try await provider.importHistory(first.file, weightUnit: .kilograms, createsMissingExercises: true) { _ in }

        let second = try await provider.prepareStrongImport(from: url)
        let secondSummary = second.summary(in: nil)
        #expect(secondSummary.alreadyImportedCount == 2)
        #expect(secondSummary.newExerciseNames.isEmpty)
        let result = try await provider.importHistory(second.file, weightUnit: .kilograms, createsMissingExercises: true) { _ in }

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
        _ = try await provider.importHistory(preview.file, weightUnit: .pounds, createsMissingExercises: true) { _ in }

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

private final class ImportTestCatalogSync: ExerciseCatalogSyncRequesting {
    func requestCatalogSync() {}
}
