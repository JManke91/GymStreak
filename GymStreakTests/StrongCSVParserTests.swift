//
//  StrongCSVParserTests.swift
//  GymStreakTests
//
//  The Strong export parser and the import's matching/conversion rules
//  (docs/history-import.md §2–§3).
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct StrongCSVParserTests {

    private let utc = TimeZone(identifier: "UTC")!
    private let header = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE"

    // MARK: - Parsing

    @Test("Rows group into workouts and consecutive exercise blocks")
    func groupsRowsIntoWorkouts() throws {
        let csv = """
        \(header)
        2024-03-05 18:01:12,Push Day,1h 5m,Bench Press (Barbell),1,60,10,0,0,
        2024-03-05 18:01:12,Push Day,1h 5m,Bench Press (Barbell),2,62.5,8,0,0,8
        2024-03-05 18:01:12,Push Day,1h 5m,Overhead Press (Barbell),1,40,8,0,0,
        2024-03-07 07:30:00,Legs,45m,Squat (Barbell),1,100,5,0,0,
        """
        let file = try StrongCSVParser.parse(csv, timeZone: utc)

        #expect(file.workouts.count == 2)
        let push = file.workouts[0]
        #expect(push.name == "Push Day")
        #expect(push.startTime == Date(timeIntervalSince1970: 1_709_661_672))
        #expect(push.duration == 3_900)
        #expect(push.exercises.map(\.name) == ["Bench Press (Barbell)", "Overhead Press (Barbell)"])
        #expect(push.exercises[0].sets == [ImportedSet(weight: 60, reps: 10), ImportedSet(weight: 62.5, reps: 8)])
        #expect(file.workouts[1].duration == 2_700)
        #expect(file.detectedWeightUnit == nil)
    }

    @Test("Quoted fields keep their commas, quotes and line breaks")
    func quotedFields() throws {
        let csv = """
        \(header),Workout Notes
        2024-03-05 18:01,"Push, heavy",30m,"Curl \"\"21s\"\"",1,10,21,0,0,,"felt good,
        strong"
        """
        let file = try StrongCSVParser.parse(csv, timeZone: utc)

        let workout = try #require(file.workouts.first)
        #expect(workout.name == "Push, heavy")
        #expect(workout.exercises.first?.name == "Curl \"21s\"")
        #expect(workout.notes == "felt good,\nstrong")
    }

    @Test("Semicolon exports with decimal commas parse; an empty RPE is fine")
    func decimalCommas() throws {
        let csv = """
        Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;Distance;Seconds;RPE
        2024-03-05 18:01:12;Push;1h;Bench Press;1;62,5;8;0;0;
        2024-03-05 18:01:12;Push;1h;Bench Press;2;"60,25";8;0;0;7,5
        """
        let file = try StrongCSVParser.parse(csv, timeZone: utc)

        #expect(file.workouts.first?.exercises.first?.sets.map(\.weight) == [62.5, 60.25])
    }

    @Test("Cardio-only rows are skipped and counted; rest-timer rows are ignored")
    func cardioRowsAreSkipped() throws {
        let csv = """
        \(header)
        2024-03-05 18:01:12,Mixed,1h,Running,1,0,0,5000,1800,
        2024-03-05 18:01:12,Mixed,1h,Running,Rest Timer,0,0,0,90,
        2024-03-05 18:01:12,Mixed,1h,Pull Up,1,0,10,0,0,
        2024-03-06 18:00:00,Run Only,30m,Rowing,1,0,0,0,600,
        """
        let file = try StrongCSVParser.parse(csv, timeZone: utc)

        #expect(file.skippedCardioSetCount == 2)
        #expect(file.workouts.count == 1, "a cardio-only workout has nothing to import")
        #expect(file.workouts[0].exercises.map(\.name) == ["Pull Up"])
        #expect(file.workouts[0].exercises[0].sets == [ImportedSet(weight: 0, reps: 10)])
    }

    @Test("Newer headers: extra columns, unit suffixes and seconds durations")
    func newerHeaderVariant() throws {
        let csv = """
        Workout #,Date,Workout Name,Duration (sec),Exercise Name,Set Order,Weight (lbs),Reps,RPE,Distance (meters),Seconds,Notes,Workout Notes
        1,2024-03-05 18:01:12,Push,3600,Bench Press,1,135,10,,0,0,,
        """
        let file = try StrongCSVParser.parse(csv, timeZone: utc)

        #expect(file.detectedWeightUnit == .pounds)
        #expect(file.workouts.first?.duration == 3_600)
        #expect(file.workouts.first?.exercises.first?.sets.first?.weight == 135)
    }

    @Test("A non-Strong CSV is rejected at the header")
    func rejectsForeignHeader() {
        let hevy = "title,start_time,end_time,description,exercise_title,set_index,weight_kg,reps\nPush,x,y,,Bench,0,60,10"
        #expect(throws: HistoryImportError.notAStrongExport) {
            try StrongCSVParser.parse(hevy, timeZone: utc)
        }
        #expect(throws: HistoryImportError.notAStrongExport) {
            try StrongCSVParser.parse("", timeZone: utc)
        }
    }

    @Test("A malformed row names its line")
    func malformedRow() {
        let csv = """
        \(header)
        2024-03-05 18:01:12,Push,1h,Bench,1,60,10,0,0,
        yesterday,Push,1h,Bench,2,60,10,0,0,
        """
        #expect(throws: HistoryImportError.malformedRow(line: 3)) {
            try StrongCSVParser.parse(csv, timeZone: utc)
        }
    }

    @Test("Duration formats")
    func durations() {
        #expect(StrongCSVParser.parseDuration("1h 5m") == 3_900)
        #expect(StrongCSVParser.parseDuration("45m") == 2_700)
        #expect(StrongCSVParser.parseDuration("50s") == 50)
        #expect(StrongCSVParser.parseDuration("3600") == 3_600)
        #expect(StrongCSVParser.parseDuration("") == 0)
    }

    // MARK: - Matching and conversion

    @Test("Names match case- and whitespace-insensitively")
    func nameNormalization() {
        #expect(HistoryImportMatching.normalizedName("  Bench   Press ") == HistoryImportMatching.normalizedName("bench press"))
        #expect(HistoryImportMatching.normalizedName("Bench\tPress") == "bench press")
    }

    @Test("Duplicate library names resolve to the oldest exercise")
    func libraryIndexPicksOldest() {
        let older = HistoryImportLibraryEntry(id: UUID(), name: "Squat", createdAt: Date(timeIntervalSince1970: 10))
        let newer = HistoryImportLibraryEntry(id: UUID(), name: "squat ", createdAt: Date(timeIntervalSince1970: 20))
        #expect(HistoryImportMatching.libraryIndex([newer, older])["squat"] == older)
    }

    @Test("Dedupe keys ignore sub-second residue and name casing")
    func dedupeKey() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(
            HistoryImportMatching.dedupeKey(name: "Push Day", startTime: start)
                == HistoryImportMatching.dedupeKey(name: "push  day", startTime: start.addingTimeInterval(0.2))
        )
        #expect(
            HistoryImportMatching.dedupeKey(name: "Push Day", startTime: start)
                != HistoryImportMatching.dedupeKey(name: "Push Day", startTime: start.addingTimeInterval(60))
        )
    }

    @Test("Pounds convert to canonical kilograms; kilograms pass through")
    func unitConversion() {
        #expect(HistoryImportMatching.storedKilograms(100, fileUnit: .kilograms) == 100)
        #expect(abs(HistoryImportMatching.storedKilograms(225, fileUnit: .pounds) - 102.0582) < 0.001)
    }

    @Test("Strong's equipment suffix shapes a created exercise")
    func customExerciseTraits() {
        #expect(HistoryImportMatching.customExerciseTraits(for: "Squat (Barbell)") == (.barbell, .resistance))
        #expect(HistoryImportMatching.customExerciseTraits(for: "Pull Up (Assisted)") == (.bodyweight, .counterweightAssistance))
        #expect(HistoryImportMatching.customExerciseTraits(for: "Face Pull") == (.dumbbell, .resistance))
    }
}
