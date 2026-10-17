//
//  HevyCSVParserTests.swift
//  GymStreakTests
//
//  The Hevy export parser (docs/history-import.md §2b): header-unit detection, superset
//  grouping, set types, notes mapping. Row shapes follow real published Hevy exports.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct HevyCSVParserTests {

    private let utc = TimeZone(identifier: "UTC")!

    static let kilogramCSV = """
    "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
    "Push","22 Dec 2025, 08:00","22 Dec 2025, 09:05","Felt strong","Bench Press",,"Pause reps",0,"warmup",40,10,,0,
    "Push","22 Dec 2025, 08:00","22 Dec 2025, 09:05","Felt strong","Bench Press",,"Pause reps",1,"normal",100,5,,0,8
    "Push","22 Dec 2025, 08:00","22 Dec 2025, 09:05","Felt strong","Bench Press",,"Pause reps",2,"failure",100,4,,0,10
    "Push","22 Dec 2025, 08:00","22 Dec 2025, 09:05","Felt strong","Cable Fly (Cable)",0,"",0,"normal",20,12,,0,
    "Push","22 Dec 2025, 08:00","22 Dec 2025, 09:05","Felt strong","Triceps Pushdown (Cable)",0,"Rope, slow",0,"dropset",30,10,,0,
    "Push","22 Dec 2025, 08:00","22 Dec 2025, 09:05","Felt strong","Treadmill",,"",0,"normal",,,1.5,600,
    "Pull","5 Jan 2026, 17:00","5 Jan 2026, 17:45","","Pull Up",,"",0,"normal",,10,,0,
    """

    @Test("Rows group into workouts; the end time gives the duration")
    func groupsRowsIntoWorkouts() throws {
        let file = try HevyCSVParser.parse(Self.kilogramCSV, timeZone: utc)

        #expect(file.workouts.map(\.name) == ["Push", "Pull"])
        let push = file.workouts[0]
        #expect(push.startTime == Date(timeIntervalSince1970: 1_766_390_400)) // 2025-12-22 08:00 UTC
        #expect(push.duration == 3_900)
        #expect(push.exercises.map(\.name) == ["Bench Press", "Cable Fly (Cable)", "Triceps Pushdown (Cable)"])
        #expect(file.workouts[1].startTime == Date(timeIntervalSince1970: 1_767_632_400)) // unpadded day
        #expect(file.workouts[1].exercises[0].sets == [ImportedSet(weight: 0, reps: 10)], "empty weight is bodyweight")
    }

    @Test("The weight column's name states the unit, so the user is not asked")
    func headerUnitDetection() throws {
        let kilograms = try HevyCSVParser.parse(Self.kilogramCSV, timeZone: utc)
        #expect(kilograms.detectedWeightUnit == .kilograms)
        #expect(kilograms.isWeightUnitCertain)

        let pounds = try HevyCSVParser.parse("""
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_miles","duration_seconds","rpe"
        "Upper","28 Mar 2025, 17:29","28 Mar 2025, 18:52","","Band Pullaparts",,"",0,"normal",,20,,0,
        "Upper","28 Mar 2025, 17:29","28 Mar 2025, 18:52","","Bench Press",,"",0,"normal",225,5,,0,
        """, timeZone: utc)
        #expect(pounds.detectedWeightUnit == .pounds)
        #expect(pounds.isWeightUnitCertain)
        #expect(pounds.workouts[0].exercises[1].sets == [ImportedSet(weight: 225, reps: 5)])
    }

    @Test("Blocks sharing a superset_id carry it; the rest carry none")
    func supersetGrouping() throws {
        let push = try HevyCSVParser.parse(Self.kilogramCSV, timeZone: utc).workouts[0]
        #expect(push.exercises.map(\.supersetGroup) == [nil, "0", "0"])
    }

    @Test("Warm-ups are skipped and counted; drop and failure sets import; cardio is skipped")
    func setTypeHandling() throws {
        let file = try HevyCSVParser.parse(Self.kilogramCSV, timeZone: utc)
        let bench = file.workouts[0].exercises[0]
        #expect(bench.sets == [ImportedSet(weight: 100, reps: 5), ImportedSet(weight: 100, reps: 4)])
        #expect(file.workouts[0].exercises[2].sets == [ImportedSet(weight: 30, reps: 10)])
        #expect(file.skippedWarmupSetCount == 1)
        #expect(file.skippedCardioSetCount == 1)
        #expect(HevyCSVParser.isWarmup("2"), "Hevy's numeric set type")
        #expect(!HevyCSVParser.isWarmup("normal"))
    }

    @Test("A period keeps only its own warm-up skips")
    func warmupsFollowThePeriod() throws {
        let file = try HevyCSVParser.parse(Self.kilogramCSV, timeZone: utc)
        let pull = file.workouts[1].startTime
        #expect(file.restricted(to: pull...pull).skippedWarmupSetCount == 0)
        #expect(file.restricted(to: pull...pull).isWeightUnitCertain)
    }

    @Test("Description becomes the notes; exercise notes are appended once each, named")
    func notesMapping() throws {
        let file = try HevyCSVParser.parse(Self.kilogramCSV, timeZone: utc)
        #expect(file.workouts[0].notes == "Felt strong\nBench Press: Pause reps\nTriceps Pushdown (Cable): Rope, slow")
        #expect(file.workouts[1].notes.isEmpty)
    }

    @Test("Dates: English or German month names, or ISO")
    func dateFormats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let expected = Date(timeIntervalSince1970: 1_760_097_600) // 2025-10-10 12:00 UTC
        #expect(HevyCSVParser.parseDate("10 Oct 2025, 12:00", calendar: calendar) == expected)
        #expect(HevyCSVParser.parseDate("10 Okt. 2025, 12:00", calendar: calendar) == expected)
        #expect(HevyCSVParser.parseDate("2025-10-10 12:00:00", calendar: calendar) == expected)
        #expect(HevyCSVParser.parseDate("Oct 10", calendar: calendar) == nil)
    }

    @Test("A Strong file is not a Hevy export, and a bad row names its line")
    func rejectsForeignAndMalformedFiles() {
        #expect(throws: HistoryImportError.unrecognizedExport) {
            _ = try HevyCSVParser.parse("""
            Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
            2024-03-05 18:01:12,Push Day,1h,Bench Press,1,100,5,0,0,
            """)
        }
        #expect(throws: HistoryImportError.malformedRow(line: 3)) {
            _ = try HevyCSVParser.parse("""
            "title","start_time","exercise_title","weight_kg","reps"
            "Push","22 Dec 2025, 08:00","Bench Press",100,5
            "Push","yesterday","Bench Press",100,5
            """)
        }
    }

    @Test("A Hevy file is not a Strong export")
    func strongParserRejectsHevy() {
        #expect(throws: HistoryImportError.unrecognizedExport) {
            _ = try StrongCSVParser.parse(Self.kilogramCSV)
        }
    }
}
