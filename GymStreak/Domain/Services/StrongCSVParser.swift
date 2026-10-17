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
/// Columns are looked up **by header name** first, so the column order and the optional
/// extras of different Strong versions all parse. **Strong localizes the header into the
/// app language** (a German export starts `Datum,Workout-Name,Dauer,Name der Übung,…`) but
/// keeps the classic column *order*, so a header with no English names falls back to that
/// order — accepted only when the first data row has a Strong timestamp in the date slot
/// and numbers in the weight and reps slots. The
/// header is the validation boundary: a file passing neither check is not a Strong export
/// and nothing is parsed.
enum StrongCSVParser {

    static func parse(_ text: String, timeZone: TimeZone = .current) throws -> ParsedHistoryFile {
        let rows = CSVTableReader.rows(from: text)
        guard let header = rows.first else { throw HistoryImportError.unrecognizedExport }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let columns = try Columns(header: header, firstRow: rows.dropFirst().first, calendar: calendar)

        var workouts: [ImportedWorkout] = []
        var workoutIndexByKey: [String: Int] = [:]
        var skippedCardio: [Date] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard row.count > columns.maxRequiredIndex else {
                throw HistoryImportError.malformedRow(line: line)
            }
            // Strong writes its rest-timer entries as rows (`Rest Timer`, `Ruhezeit`, … —
            // localized); they are not sets.
            if !isSetOrder(row[columns.setOrder]) { continue }

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
                if distance > 0 || seconds > 0 { skippedCardio.append(startTime) }
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
            skippedCardioSetStartTimes: skippedCardio,
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

        init(header: [String], firstRow: [String]?, calendar: Calendar) throws {
            let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if !names.contains("date"), let firstRow,
               (10...12).contains(names.count),
               firstRow.count > 6,
               StrongCSVParser.parseDate(firstRow[0], calendar: calendar) != nil,
               StrongCSVParser.parseNumber(firstRow[5]) != nil,
               StrongCSVParser.parseNumber(firstRow[6]) != nil {
                self.init(classicLayoutOf: names)
            } else {
                try self.init(namedColumns: names)
            }
        }

        private init(namedColumns names: [String]) throws {
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
            else { throw HistoryImportError.unrecognizedExport }

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

            detectedWeightUnit = Self.unit(inWeightHeader: names[weight])
        }

        /// The classic export order, whatever language the header is in:
        /// `Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance,
        /// Seconds, [Notes, Workout Notes,] RPE`.
        private init(classicLayoutOf names: [String]) {
            date = 0
            workoutName = 1
            duration = 2
            exerciseName = 3
            setOrder = 4
            weight = 5
            reps = 6
            distance = 7
            seconds = 8
            workoutNotes = names.count == 12 ? 10 : nil
            detectedWeightUnit = Self.unit(inWeightHeader: names[5])
        }

        private static func unit(inWeightHeader header: String) -> WeightUnit? {
            if header.contains("lb") { return .pounds }
            if header.contains("kg") { return .kilograms }
            return nil
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

    /// `1h 5min`, `43min`, `45m`, `30s`, or plain seconds (`Duration (sec)` exports).
    /// Unknown → 0.
    static func parseDuration(_ raw: String) -> TimeInterval {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let seconds = Double(trimmed) { return max(seconds, 0) }
        var total: TimeInterval = 0
        for token in trimmed.split(separator: " ") {
            let number = token.prefix { $0.isNumber || $0 == "." || $0 == "," }
            let unit = token.dropFirst(number.count).lowercased()
            guard let value = Double(number.replacingOccurrences(of: ",", with: ".")) else { continue }
            if unit.hasPrefix("h") {
                total += value * 3600
            } else if unit.hasPrefix("m") {
                total += value * 60
            } else if unit.hasPrefix("s") {
                total += value
            }
        }
        return total
    }

    /// A set row's `Set Order` is a number, or a one-letter marker (`W`/`D`/`F`, warm-up,
    /// drop, failure). Anything longer is a rest-timer row in some language.
    static func isSetOrder(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 1 || Int(trimmed) != nil
    }
}
