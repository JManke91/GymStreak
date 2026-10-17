//
//  HevyCSVParser.swift
//  GymStreak
//
//  Maps Hevy's `workout_data.csv` export onto `ParsedHistoryFile`
//  (docs/history-import.md §2b). Pure: no store, no file access.
//

import Foundation

/// Parses a Hevy export: one row per set, columns
/// `title, start_time, end_time, description, exercise_title, superset_id, exercise_notes,
/// set_index, set_type, weight_kg|weight_lbs, reps, distance_km|distance_miles,
/// duration_seconds, rpe`.
///
/// Columns are looked up by header name. The header is the validation boundary: without
/// the required columns the file is not a Hevy export and nothing is parsed. Unlike
/// Strong, the weight column **names its unit**, so the user is not asked.
enum HevyCSVParser {

    static func parse(_ text: String, timeZone: TimeZone = .current) throws -> ParsedHistoryFile {
        let rows = CSVTableReader.rows(from: text)
        guard let header = rows.first else { throw HistoryImportError.unrecognizedExport }
        let columns = try Columns(header: header)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var workouts: [ImportedWorkout] = []
        var workoutIndexByKey: [String: Int] = [:]
        // Exercise notes repeat on every set row; each block contributes its note once.
        var notedBlocks: Set<String> = []
        var skippedCardio: [Date] = []
        var skippedWarmup: [Date] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard row.count > columns.maxRequiredIndex else {
                throw HistoryImportError.malformedRow(line: line)
            }
            guard let startTime = parseDate(row[columns.startTime], calendar: calendar),
                  let weight = StrongCSVParser.parseNumber(row[columns.weight]),
                  let reps = StrongCSVParser.parseNumber(row[columns.reps])
            else { throw HistoryImportError.malformedRow(line: line) }

            let title = row[columns.title].trimmingCharacters(in: .whitespaces)
            let exerciseName = row[columns.exerciseTitle].trimmingCharacters(in: .whitespaces)
            guard !exerciseName.isEmpty else { throw HistoryImportError.malformedRow(line: line) }

            if columns.setType.map({ isWarmup(row[safe: $0]) }) == true {
                skippedWarmup.append(startTime)
                continue
            }
            if weight == 0 && reps == 0 {
                let distance = columns.distance.flatMap { StrongCSVParser.parseNumber(row[safe: $0]) } ?? 0
                let seconds = columns.durationSeconds.flatMap { StrongCSVParser.parseNumber(row[safe: $0]) } ?? 0
                if distance > 0 || seconds > 0 { skippedCardio.append(startTime) }
                continue
            }

            let key = HistoryImportMatching.dedupeKey(name: title, startTime: startTime)
            let index: Int
            if let existing = workoutIndexByKey[key] {
                index = existing
            } else {
                index = workouts.count
                workoutIndexByKey[key] = index
                let endTime = columns.endTime.flatMap { parseDate(row[safe: $0], calendar: calendar) }
                workouts.append(ImportedWorkout(
                    name: title,
                    startTime: startTime,
                    duration: endTime.map { max($0.timeIntervalSince(startTime), 0) } ?? 0,
                    notes: columns.description.map { row[safe: $0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? "",
                    exercises: []
                ))
            }

            let group = columns.supersetId
                .map { row[safe: $0].trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let set = ImportedSet(weight: abs(weight), reps: Int(reps.rounded()))
            // Consecutive rows of one exercise (in one superset) form one block; the same
            // exercise reappearing later in the workout is a new block, as it was trained.
            if let last = workouts[index].exercises.last, last.name == exerciseName, last.supersetGroup == group {
                workouts[index].exercises[workouts[index].exercises.count - 1].sets.append(set)
            } else {
                workouts[index].exercises.append(ImportedExercise(name: exerciseName, sets: [set], supersetGroup: group))
            }

            // History has no per-exercise notes: append them to the workout's, named.
            let blockKey = "\(index)|\(workouts[index].exercises.count)"
            if let notesColumn = columns.exerciseNotes, !notedBlocks.contains(blockKey) {
                let note = row[safe: notesColumn].trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    notedBlocks.insert(blockKey)
                    let entry = "\(exerciseName): \(note)"
                    workouts[index].notes = workouts[index].notes.isEmpty
                        ? entry
                        : workouts[index].notes + "\n" + entry
                }
            }
        }

        guard !workouts.isEmpty else { throw HistoryImportError.noWorkouts }
        return ParsedHistoryFile(
            workouts: workouts,
            skippedCardioSetStartTimes: skippedCardio,
            detectedWeightUnit: columns.weightUnit,
            isWeightUnitCertain: true,
            skippedWarmupSetStartTimes: skippedWarmup
        )
    }

    // MARK: - Header

    private struct Columns {
        let title: Int
        let startTime: Int
        let exerciseTitle: Int
        let weight: Int
        let reps: Int
        let weightUnit: WeightUnit
        let endTime: Int?
        let description: Int?
        let supersetId: Int?
        let exerciseNotes: Int?
        let setType: Int?
        let distance: Int?
        let durationSeconds: Int?

        var maxRequiredIndex: Int { [title, startTime, exerciseTitle, weight, reps].max() ?? 0 }

        init(header: [String]) throws {
            let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            func index(_ name: String) -> Int? { names.firstIndex(of: name) }

            let kilograms = index("weight_kg")
            guard let title = index("title"),
                  let startTime = index("start_time"),
                  let exerciseTitle = index("exercise_title"),
                  let weight = kilograms ?? index("weight_lbs"),
                  let reps = index("reps")
            else { throw HistoryImportError.unrecognizedExport }

            self.title = title
            self.startTime = startTime
            self.exerciseTitle = exerciseTitle
            self.weight = weight
            self.reps = reps
            weightUnit = kilograms != nil ? .kilograms : .pounds
            endTime = index("end_time")
            description = index("description")
            supersetId = index("superset_id")
            exerciseNotes = index("exercise_notes")
            setType = index("set_type")
            distance = index("distance_km") ?? index("distance_miles")
            durationSeconds = index("duration_seconds")
        }
    }

    // MARK: - Fields

    /// `22 Dec 2025, 08:00` (day not always zero-padded), wall-clock time in `calendar`'s
    /// zone. Month names are read by their first three letters, English or German, since a
    /// localized export is unconfirmed. An ISO `2025-12-22 08:00[:ss]` is accepted too.
    static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        if let iso = StrongCSVParser.parseDate(raw, calendar: calendar) { return iso }
        let parts = raw.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
        guard parts.count == 4,
              let day = Int(parts[0]),
              let month = month(parts[1]),
              let year = Int(parts[2])
        else { return nil }
        let time = parts[3].split(separator: ":").compactMap { Int($0) }
        guard time.count == 2 || time.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: time[0], minute: time[1], second: time.count == 3 ? time[2] : 0
        ))
    }

    private static let monthsByPrefix: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "mär": 3, "mrz": 3, "apr": 4, "may": 5, "mai": 5,
        "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "okt": 10, "nov": 11, "dec": 12, "dez": 12,
    ]

    private static func month(_ raw: Substring) -> Int? {
        monthsByPrefix[String(raw.lowercased().prefix(3))]
    }

    /// `warmup` (or Hevy's numeric `2`). `normal`, `dropset` and `failure` are ordinary sets.
    static func isWarmup(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return value == "warmup" || value == "warm_up" || value == "2"
    }
}
