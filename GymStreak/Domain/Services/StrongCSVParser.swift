//
//  StrongCSVParser.swift
//  GymStreak
//
//  Maps Strong's workout CSV export onto `ParsedHistoryFile`
//  (docs/history-import.md §2). Pure: no store, no file access.
//

import Foundation

/// Parses a Strong export: one row per set, columns
/// `Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance,
/// Seconds, RPE` (newer exports add `Notes`, `Workout Notes`, `Workout #` and unit
/// suffixes such as `Weight (kg)` / `Duration (sec)`).
///
/// Columns are looked up **by header name**, never by position, so the column order
/// and the optional extras of different Strong versions all parse. The header is the
/// validation boundary: without the six required columns the file is not a Strong
/// export and nothing is parsed.
enum StrongCSVParser {

    static func parse(_ text: String, timeZone: TimeZone = .current) throws -> ParsedHistoryFile {
        let rows = CSVTableReader.rows(from: text)
        guard let header = rows.first else { throw HistoryImportError.notAStrongExport }
        let columns = try Columns(header: header)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var workouts: [ImportedWorkout] = []
        var workoutIndexByKey: [String: Int] = [:]
        var skippedCardio = 0

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard row.count > columns.maxRequiredIndex else {
                throw HistoryImportError.malformedRow(line: line)
            }
            // Strong writes its rest-timer entries as rows; they are not sets.
            let setOrder = row[columns.setOrder].lowercased()
            if setOrder.contains("rest") { continue }

            guard let startTime = parseDate(row[columns.date], calendar: calendar),
                  let weight = parseNumber(row[columns.weight]),
                  let reps = parseNumber(row[columns.reps])
            else { throw HistoryImportError.malformedRow(line: line) }

            let workoutName = row[columns.workoutName].trimmingCharacters(in: .whitespaces)
            let exerciseName = row[columns.exerciseName].trimmingCharacters(in: .whitespaces)
            guard !exerciseName.isEmpty else { throw HistoryImportError.malformedRow(line: line) }

            if weight == 0 && reps == 0 {
                let distance = columns.distance.flatMap { parseNumber(row[safe: $0]) } ?? 0
                let seconds = columns.seconds.flatMap { parseNumber(row[safe: $0]) } ?? 0
                if distance > 0 || seconds > 0 { skippedCardio += 1 }
                continue
            }

            let key = HistoryImportMatching.dedupeKey(name: workoutName, startTime: startTime)
            let index: Int
            if let existing = workoutIndexByKey[key] {
                index = existing
            } else {
                index = workouts.count
                workoutIndexByKey[key] = index
                workouts.append(ImportedWorkout(
                    name: workoutName,
                    startTime: startTime,
                    duration: columns.duration.map { parseDuration(row[safe: $0]) } ?? 0,
                    notes: "",
                    exercises: []
                ))
            }

            if workouts[index].notes.isEmpty, let notesColumn = columns.workoutNotes {
                workouts[index].notes = row[safe: notesColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let set = ImportedSet(weight: abs(weight), reps: Int(reps.rounded()))
            // Consecutive rows of one exercise form one block; the same exercise
            // reappearing later in the workout is a new block, as it was trained.
            if let last = workouts[index].exercises.last, last.name == exerciseName {
                workouts[index].exercises[workouts[index].exercises.count - 1].sets.append(set)
            } else {
                workouts[index].exercises.append(ImportedExercise(name: exerciseName, sets: [set]))
            }
        }

        guard !workouts.isEmpty else { throw HistoryImportError.noWorkouts }
        return ParsedHistoryFile(
            workouts: workouts,
            skippedCardioSetCount: skippedCardio,
            detectedWeightUnit: columns.detectedWeightUnit
        )
    }

    // MARK: - Header

    private struct Columns {
        let date: Int
        let workoutName: Int
        let exerciseName: Int
        let setOrder: Int
        let weight: Int
        let reps: Int
        let duration: Int?
        let distance: Int?
        let seconds: Int?
        let workoutNotes: Int?
        let detectedWeightUnit: WeightUnit?

        var maxRequiredIndex: Int { [date, workoutName, exerciseName, setOrder, weight, reps].max() ?? 0 }

        init(header: [String]) throws {
            let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            func exact(_ name: String) -> Int? { names.firstIndex(of: name) }
            // `Weight (kg)`, `Duration (sec)`, `Distance (meters)` …
            func prefixed(_ name: String) -> Int? {
                names.firstIndex { $0 == name || $0.hasPrefix(name + " (") }
            }

            guard let date = exact("date"),
                  let workoutName = exact("workout name"),
                  let exerciseName = exact("exercise name"),
                  let setOrder = exact("set order"),
                  let weight = prefixed("weight"),
                  let reps = exact("reps")
            else { throw HistoryImportError.notAStrongExport }

            self.date = date
            self.workoutName = workoutName
            self.exerciseName = exerciseName
            self.setOrder = setOrder
            self.weight = weight
            self.reps = reps
            self.duration = prefixed("duration")
            self.distance = prefixed("distance")
            self.seconds = exact("seconds")
            self.workoutNotes = exact("workout notes")

            let weightHeader = names[weight]
            if weightHeader.contains("lb") {
                detectedWeightUnit = .pounds
            } else if weightHeader.contains("kg") {
                detectedWeightUnit = .kilograms
            } else {
                detectedWeightUnit = nil
            }
        }
    }

    // MARK: - Fields

    /// `2024-03-05 18:01:12` or `2024-03-05 18:01`, wall-clock time in `calendar`'s zone.
    /// Built from components rather than a `DateFormatter`, which is costly to create
    /// and not `Sendable`.
    static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, time.count == 2 || time.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: day[0], month: day[1], day: day[2],
            hour: time[0], minute: time[1], second: time.count == 3 ? time[2] : 0
        ))
    }

    /// Empty → 0. Accepts a decimal comma (`62,5`). Nil only for a non-number.
    static func parseNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// `1h 5m`, `45m`, `30s`, or plain seconds (`Duration (sec)` exports). Unknown → 0.
    static func parseDuration(_ raw: String) -> TimeInterval {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let seconds = Double(trimmed) { return max(seconds, 0) }
        var total: TimeInterval = 0
        for token in trimmed.split(separator: " ") {
            guard let unit = token.last, let value = Double(token.dropLast()) else { continue }
            switch unit {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: continue
            }
        }
        return total
    }
}

private extension Array where Element == String {
    /// Optional columns may be missing from a short row; treat that as empty.
    subscript(safe index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}
