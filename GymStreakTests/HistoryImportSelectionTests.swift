//
//  HistoryImportSelectionTests.swift
//  GymStreakTests
//
//  The import's period filter (docs/history-import.md §3b): presets, the live preview
//  summary, and that only the selected workouts reach the importer.
//

import Foundation
import Synchronization
import Testing
@testable import GymStreak

@Suite
@MainActor
struct HistoryImportSelectionTests {

    nonisolated private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2024-01-10, 2024-05-20 and 2024-06-15 (18:00 UTC); the last two share "Bench Press".
    nonisolated private static let file: ParsedHistoryFile = {
        func day(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: 18))!
        }
        func workout(_ date: Date, _ exercises: [String]) -> ImportedWorkout {
            ImportedWorkout(
                name: "Push", startTime: date, duration: 3_600, notes: "",
                exercises: exercises.map { ImportedExercise(name: $0, sets: [ImportedSet(weight: 50, reps: 5)]) }
            )
        }
        return ParsedHistoryFile(
            workouts: [
                workout(day(1, 10), ["Squat (Barbell)"]),
                workout(day(5, 20), ["Bench Press", "Cable Fly (Cable)"]),
                workout(day(6, 15), ["Bench Press"]),
            ],
            skippedCardioSetStartTimes: [day(1, 10), day(6, 15)],
            detectedWeightUnit: nil
        )
    }()

    nonisolated private static let preview = HistoryImportPreview(
        file: file,
        earliest: file.workouts[0].startTime,
        latest: file.workouts[2].startTime,
        alreadyImportedKeys: [HistoryImportMatching.dedupeKey(name: "Push", startTime: file.workouts[2].startTime)],
        libraryMatchedNames: ["bench press"]
    )

    @Test("The whole-file summary counts every workout")
    func wholeFileSummary() {
        let summary = Self.preview.summary(in: nil)
        #expect(summary == HistoryImportSelectionSummary(
            workoutCount: 3, alreadyImportedCount: 1, matchedExerciseCount: 1,
            newExerciseNames: ["Cable Fly (Cable)", "Squat (Barbell)"], skippedCardioSetCount: 2
        ))
    }

    @Test("A period narrows workouts, duplicates, new exercises and cardio skips together")
    func periodSummary() {
        let range = Self.file.workouts[1].startTime...Self.file.workouts[2].startTime
        let summary = Self.preview.summary(in: range)
        #expect(summary.workoutCount == 2)
        #expect(summary.alreadyImportedCount == 1)
        #expect(summary.newExerciseNames == ["Cable Fly (Cable)"], "Squat is only trained outside the period")
        #expect(summary.skippedCardioSetCount == 1)
    }

    /// Regression (2026-10-10, device): a period holding only an already-imported workout
    /// still offered Import and listed seven "new" exercises that would never be created.
    @Test("A fully imported period has nothing importable and promises no new exercises")
    func fullyImportedPeriod() {
        let range = Self.file.workouts[2].startTime...Self.file.workouts[2].startTime
        let summary = Self.preview.summary(in: range)
        #expect(summary.workoutCount == 1)
        #expect(summary.alreadyImportedCount == 1)
        #expect(summary.importableWorkoutCount == 0)
        #expect(summary.newExerciseNames.isEmpty)
        #expect(summary.matchedExerciseCount == 0)
    }

    @Test("Presets count back from the newest workout and never start before the first")
    func presets() {
        let earliest = Self.file.workouts[0].startTime
        let latest = Self.file.workouts[2].startTime
        let month = HistoryImportPeriod.lastMonth.dayRange(earliest: earliest, latest: latest, calendar: Self.calendar)
        #expect(month.start == Self.calendar.date(byAdding: .month, value: -1, to: latest))
        #expect(month.end == latest)
        let year = HistoryImportPeriod.lastYear.dayRange(earliest: earliest, latest: latest, calendar: Self.calendar)
        #expect(year.start == earliest)
        let all = HistoryImportPeriod.everything.dayRange(earliest: earliest, latest: latest, calendar: Self.calendar)
        #expect(all == (earliest, latest))
    }

    @Test("Only the selected period reaches the importer")
    func importsOnlySelectedPeriod() async throws {
        let importer = RecordingImporter(preview: Self.preview)
        let viewModel = HistoryImportViewModel(
            source: .strong,
            importer: importer,
            catalogSync: SelectionTestCatalogSync(),
            weightUnitPreference: SelectionTestUnitPreference()
        )
        await viewModel.fileSelected(.success(URL(fileURLWithPath: "/strong.csv")))
        #expect(viewModel.selection?.workoutCount == 3)
        #expect(viewModel.activePeriod == .everything)

        viewModel.apply(.lastMonth)
        #expect(viewModel.selection?.workoutCount == 2, "May 20 and June 15 both lie within a month of June 15")
        #expect(viewModel.activePeriod == .lastMonth)

        viewModel.rangeStart = Self.file.workouts[2].startTime
        #expect(viewModel.selection?.workoutCount == 1)
        #expect(viewModel.activePeriod == nil, "a hand-picked range is custom")

        // Only June 15 is selected, and it is already imported: Import does nothing.
        await viewModel.startImport()
        #expect(importer.importedFile.withLock { $0 } == nil)

        viewModel.rangeStart = Self.file.workouts[1].startTime
        await viewModel.startImport()
        let imported = try #require(importer.importedFile.withLock { $0 })
        #expect(imported.workouts.map(\.startTime) == Self.file.workouts[1...2].map(\.startTime))
        #expect(imported.skippedCardioSetCount == 1)
    }
}

// MARK: - Doubles

private final class RecordingImporter: HistoryImporting {
    let preview: HistoryImportPreview
    let importedFile = Mutex<ParsedHistoryFile?>(nil)

    init(preview: HistoryImportPreview) { self.preview = preview }

    func prepareImport(from url: URL, source: HistoryImportSource) async throws -> HistoryImportPreview { preview }

    func importHistory(
        _ file: ParsedHistoryFile,
        weightUnit: WeightUnit,
        createsMissingExercises: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HistoryImportResult {
        importedFile.withLock { $0 = file }
        return HistoryImportResult(
            importedWorkoutCount: file.workouts.count, skippedDuplicateCount: 0,
            createdExerciseCount: 0, skippedCardioSetCount: file.skippedCardioSetCount
        )
    }
}

private final class SelectionTestCatalogSync: ExerciseCatalogSyncRequesting {
    func requestCatalogSync() {}
}

private final class SelectionTestUnitPreference: WeightUnitPreferenceProviding {
    var weightUnit: WeightUnit = .kilograms
}
