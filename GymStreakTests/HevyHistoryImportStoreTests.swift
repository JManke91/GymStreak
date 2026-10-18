//
//  HevyHistoryImportStoreTests.swift
//  GymStreakTests
//
//  A Hevy export through the shared import pipeline against a real (in-memory) store:
//  supersets in history, warm-ups left out, idempotency (docs/history-import.md §2b).
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct HevyHistoryImportStoreTests {

    @Test("A Hevy file lands in history with its supersets grouped")
    func importsWithSupersets() async throws {
        let (container, provider) = try makeStore()
        let preview = try await provider.prepareImport(from: try writeFile(HevyCSVParserTests.kilogramCSV), source: .hevy)
        let summary = preview.summary(in: nil)
        #expect(summary.workoutCount == 2)
        #expect(summary.skippedWarmupSetCount == 1)
        #expect(summary.skippedCardioSetCount == 1)
        #expect(preview.file.isWeightUnitCertain)

        let result = try await provider.importHistory(preview.file, weightUnit: .kilograms, createsMissingExercises: true) { _ in }
        #expect(result.importedWorkoutCount == 2)
        #expect(result.skippedWarmupSetCount == 1)

        let context = ModelContext(container)
        let push = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.routineName == "Push" })
        #expect(push.notes.hasPrefix("Felt strong"))
        let groups = push.exercisesGroupedBySupersets
        #expect(groups.map { $0.map(\.exerciseName) } == [
            ["Bench Press"], ["Cable Fly (Cable)", "Triceps Pushdown (Cable)"],
        ])
        let superset = groups[1]
        #expect(superset[0].supersetId != nil)
        #expect(superset[0].supersetId == superset[1].supersetId)
        #expect(superset.map(\.supersetOrder) == [0, 1])
        #expect(groups[0][0].supersetId == nil)
        #expect(groups[0][0].setsList.count == 2, "the warm-up set is not imported")
        // The History detail draws its rows from this — an imported superset shows grouped
        // there with no import-side change (docs/history-import.md §3).
        let rows = WorkoutDetailExerciseGroup.make(from: push)
        #expect(rows.map(\.supersetLetter) == [nil, "A"])
        #expect(rows[1].exercises.map(\.name) == ["Cable Fly (Cable)", "Triceps Pushdown (Cable)"])
    }

    @Test("Superset ids are scoped per workout")
    func supersetIdsAreScopedPerWorkout() async throws {
        let (container, provider) = try makeStore()
        let preview = try await provider.prepareImport(from: try writeFile("""
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "A","1 Feb 2026, 10:00","1 Feb 2026, 11:00","","Curl",0,"",0,"normal",10,10,,0,
        "A","1 Feb 2026, 10:00","1 Feb 2026, 11:00","","Dip",0,"",0,"normal",0,10,,0,
        "B","3 Feb 2026, 10:00","3 Feb 2026, 11:00","","Curl",0,"",0,"normal",12,10,,0,
        "B","3 Feb 2026, 10:00","3 Feb 2026, 11:00","","Dip",0,"",0,"normal",0,12,,0,
        """), source: .hevy)
        _ = try await provider.importHistory(preview.file, weightUnit: .kilograms, createsMissingExercises: true) { _ in }

        let ids = try ModelContext(container).fetch(FetchDescriptor<WorkoutExercise>()).compactMap(\.supersetId)
        #expect(ids.count == 4)
        #expect(Set(ids).count == 2, "one superset per workout, not one shared across both")
    }

    @Test("Re-importing a Hevy file creates nothing; pounds are stored as kilograms")
    func reimportAndPounds() async throws {
        let (container, provider) = try makeStore()
        let url = try writeFile("""
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_miles","duration_seconds","rpe"
        "Upper","28 Mar 2025, 17:29","28 Mar 2025, 18:52","","Bench Press",,"",0,"normal",225,5,,0,
        """)
        let first = try await provider.prepareImport(from: url, source: .hevy)
        _ = try await provider.importHistory(first.file, weightUnit: first.file.detectedWeightUnit ?? .kilograms, createsMissingExercises: true) { _ in }
        let second = try await provider.prepareImport(from: url, source: .hevy)
        let result = try await provider.importHistory(second.file, weightUnit: .pounds, createsMissingExercises: true) { _ in }

        #expect(result.importedWorkoutCount == 0)
        #expect(result.skippedDuplicateCount == 1)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        let weight = try #require(try context.fetch(FetchDescriptor<WorkoutSet>()).first?.actualWeight)
        #expect(abs(weight - WeightUnit.pounds.kilograms(fromDisplay: 225)) < 0.0001)
    }

    @Test("A Strong file chosen as Hevy is rejected and writes nothing")
    func strongFileInHevyFlowWritesNothing() async throws {
        let (container, provider) = try makeStore()
        let url = try writeFile("""
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
        2024-03-05 18:01:12,Push Day,1h,Bench Press,1,100,5,0,0,
        """)
        await #expect(throws: HistoryImportError.unrecognizedExport) {
            _ = try await provider.prepareImport(from: url, source: .hevy)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    // MARK: - Helpers

    private func makeStore() throws -> (ModelContainer, any HistoryImporting) {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        context.insert(Exercise(name: "Bench Press", equipmentType: .barbell))
        try context.save()
        return (container, SwiftDataHistoryImportProvider(modelContainer: container, gate: .unshared()))
    }

    private func writeFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hevy-\(UUID().uuidString).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
