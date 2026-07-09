//
//  ChatFactService.swift
//  GymStreak
//
//  Tool-backing data layer for the chat assistant. Queries SwiftData directly
//  and delegates every computation to the existing domain services
//  (`WorkoutPlanningService`, `PersonalRecordService`-style 1RM math,
//  `HistoryStatsService`). Returns compact fact lines; the model only verbalizes
//  them. See docs/ai-coach-chat-feasibility.md.
//
//  Spike simplification: fact lines are emitted in compact canonical English and
//  the model translates to the user's language (the Instructions carry a small
//  DE glossary, mirroring the Workout Analysis surface). Localizing the fact
//  lines themselves is listed as post-spike work.
//

import Foundation
import SwiftData

@MainActor
final class ChatFactService: ChatFactProviding {

    private let modelContext: ModelContext
    private let nameResolver = ExerciseNameResolver()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Next workout

    func nextWorkoutFacts() -> String {
        let routines = (try? modelContext.fetch(FetchDescriptor<Routine>())) ?? []
        let completed = completedSessions()

        struct Due { let name: String; let date: Date }
        var dues: [Due] = []

        for routine in routines {
            guard let schedule = routine.schedule, schedule.isActive else { continue }
            let lastCompleted = completed
                .filter { $0.routine?.id == routine.id }
                .map(\.startTime)
                .max()
            guard let next = WorkoutPlanningService.nextDue(
                for: schedule,
                lastCompleted: lastCompleted
            ) else { continue }
            dues.append(Due(name: routine.name, date: next))
        }

        guard !dues.isEmpty else {
            return "No routines are scheduled. The user has not set up a training plan."
        }

        let lines = dues
            .sorted { $0.date < $1.date }
            .map { "- \($0.name): \(describeDue($0.date))" }
            .joined(separator: "\n")

        return "Next scheduled workouts:\n\(lines)"
    }

    // MARK: - Exercise PR

    func exercisePRFacts(exerciseName: String) -> String {
        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []

        switch nameResolver.resolve(exerciseName, in: library) {
        case .noMatch:
            return noMatchPayload(library: library)

        case .ambiguous(let names):
            return "\"\(exerciseName)\" is ambiguous. Candidates: \(names.joined(separator: ", ")). Ask the user which one they mean."

        case .resolved(let exercises):
            return personalRecordLine(for: exercises)
        }
    }

    /// No lexical match. Returns a machine-marked, data-only payload — NOT a
    /// user-facing sentence — because the on-device model otherwise translates a
    /// prose result verbatim into its answer (observed: it echoed the guidance to
    /// the user). The `__NO_MATCH__` sigil is handled by the system prompt, which
    /// tells the model to re-call `getExercisePR` with the matching listed name
    /// (cross-language mapping) and never reveal this text. Bounded to the real
    /// library so the model can map but never invent. See docs.
    private func noMatchPayload(library: [Exercise]) -> String {
        let names = nameResolver.sortedUniqueNames(library)
        guard !names.isEmpty else { return "__NO_MATCH__ exercises: (none)" }
        let capped = names.prefix(60)
        let more = names.count > capped.count ? ", +\(names.count - capped.count) more" : ""
        return "__NO_MATCH__ exercises: \(capped.joined(separator: ", "))\(more)"
    }

    /// Best-ever set (by estimated 1RM, Epley) for a resolved exercise. When the
    /// user has several library entries with the same name (e.g. barbell + dumbbell
    /// "Biceps Curls"), `exercises` holds all of them and the record is taken across
    /// all — they are one exercise to the user and can't be told apart by name.
    private func personalRecordLine(for exercises: [Exercise]) -> String {
        let sessions = completedSessions()
        let displayName = exercises.first?.name ?? ""
        var best: (weight: Double, reps: Int, est: Double, date: Date)?

        for session in sessions {
            for workoutExercise in session.workoutExercisesList
            where exercises.contains(where: { nameResolver.matches(workoutExercise, $0) }) {
                let usePlanned = workoutExercise.progressiveOverloadApplied
                for set in workoutExercise.setsList where set.isCompleted {
                    let weight = usePlanned ? set.plannedWeight : set.actualWeight
                    let reps = usePlanned ? set.plannedReps : set.actualReps
                    guard weight > 0, reps > 0 else { continue }
                    let est = weight * (1 + Double(reps) / 30.0)
                    if est > (best?.est ?? 0) {
                        best = (weight, reps, est, session.startTime)
                    }
                }
            }
        }

        guard let best else {
            return "\(displayName): no completed sets logged yet, so there is no personal record."
        }

        return "\(displayName) personal record: best set \(fmt(best.weight)) kg x \(best.reps) reps, estimated 1RM \(fmt(best.est)) kg, achieved on \(mediumDate(best.date))."
    }

    // MARK: - Workout history

    func workoutHistoryFacts(timeframe: ChatHistoryTimeframe) -> String {
        let sessions = completedSessions()
        let range = interval(for: timeframe)
        let inRange = sessions.filter { range.contains($0.startTime) }

        let count = inRange.count
        let volume = inRange.reduce(0.0) { $0 + $1.totalVolume }
        let streak = HistoryStatsService.streakWeeks(sessions: sessions)
        let label = timeframeLabel(timeframe)

        var parts = ["\(label): \(count) workout\(count == 1 ? "" : "s"), total volume \(fmt(volume)) kg."]

        if let last = inRange.max(by: { $0.startTime < $1.startTime }) {
            let minutes = Int(last.duration / 60)
            parts.append("Most recent in this period: \(last.routineName) on \(weekday(last.startTime)), \(minutes) min.")
        }

        parts.append("Current streak: \(streak) week\(streak == 1 ? "" : "s").")
        return parts.joined(separator: " ")
    }

    // MARK: - Fetch helpers

    private func completedSessions() -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Timeframe

    private func interval(for timeframe: ChatHistoryTimeframe) -> DateInterval {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let now = Date()
        switch timeframe {
        case .thisWeek:
            return HistoryStatsService.weekInterval(containing: now, calendar: calendar)
        case .lastWeek:
            let lastWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return HistoryStatsService.weekInterval(containing: lastWeek, calendar: calendar)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
                ?? DateInterval(start: now, duration: 0)
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return calendar.dateInterval(of: .month, for: lastMonth)
                ?? DateInterval(start: lastMonth, duration: 0)
        case .allTime:
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    private func timeframeLabel(_ timeframe: ChatHistoryTimeframe) -> String {
        switch timeframe {
        case .thisWeek: return "This week"
        case .lastWeek: return "Last week"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .allTime: return "All time"
        }
    }

    // MARK: - Formatting

    /// Human phrase for a due date relative to today (weekday + signed day gap).
    /// Kept in compact canonical form; the model phrases it in the user's language.
    private func describeDue(_ date: Date) -> String {
        let calendar = HistoryStatsService.isoGermanCalendar()
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        let gap = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let weekdayName = weekday(date)

        if gap == 0 { return "due today (\(weekdayName))" }
        if gap == 1 { return "due tomorrow (\(weekdayName))" }
        if gap > 1 { return "due \(weekdayName), in \(gap) days" }
        if gap == -1 { return "overdue by 1 day (was due \(weekdayName))" }
        return "overdue by \(-gap) days (was due \(weekdayName))"
    }

    // Fact lines are uniformly English (canonical); the model translates the whole
    // line into the user's reply language, so weekday/month names must NOT come out
    // in the device locale (that caused "…due Samstag, in 2 days" in an English reply).
    private static let factLocale = Locale(identifier: "en_US")

    private func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.factLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.factLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Trims a trailing `.0` so "37.5" and "40" both read cleanly.
    private func fmt(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
