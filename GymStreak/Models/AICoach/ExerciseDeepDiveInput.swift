//
//  ExerciseDeepDiveInput.swift
//  GymStreak
//

import FoundationModels

@Generable
struct ExerciseDeepDiveInput {
    @Guide(description: "User's locale identifier, e.g. 'de_DE' or 'en_US'")
    let locale: String

    @Guide(description: "Name of the exercise being analyzed")
    let exerciseName: String

    @Guide(description: "Total number of sessions in which this exercise was performed")
    let totalSessions: Int

    @Guide(description: "Date range of recorded history for this exercise, e.g. '2024-05 to 2026-04'")
    let historyRange: String

    @Guide(description: "Overall progression from first to most recent session")
    let overallProgression: ProgressionSummary

    @Guide(description: "The single best performance point across all history")
    let peak: PerformancePoint

    @Guide(description: "The strongest improvement segment found in the history")
    let strongestSegment: ProgressionSegment

    @Guide(description: "The most recent 4–8 week segment of training")
    let currentSegment: ProgressionSegment
}

@Generable
struct ProgressionSummary {
    @Guide(description: "Absolute change in estimated 1RM from first to most recent session, in kilograms (negative means regression)")
    let estimatedOneRMDeltaKg: Double

    @Guide(description: "Percentage change in estimated 1RM from first to most recent session (negative means regression)")
    let percentChange: Int
}

@Generable
struct PerformancePoint {
    @Guide(description: "Weight lifted in kilograms for this performance")
    let weightKg: Double

    @Guide(description: "Number of reps performed")
    let reps: Int

    @Guide(description: "Estimated 1RM calculated via Epley formula, in kilograms")
    let estimatedOneRMKg: Double

    @Guide(description: "Human-readable month label when this performance occurred, e.g. 'March 2026'")
    let monthLabel: String
}

@Generable
struct ProgressionSegment {
    @Guide(description: "Classification of this segment: 'improving', 'plateau', or 'regressing'")
    let classification: String

    @Guide(description: "Human-readable date range for this segment, e.g. 'February to April 2026'")
    let range: String

    @Guide(description: "Average number of sessions per week during this segment")
    let avgSessionsPerWeek: Double

    @Guide(description: "Human-readable magnitude of change during this segment, e.g. '+5kg est. 1RM' or 'stable'")
    let magnitude: String
}

// MARK: - Prompt Serialisation

extension ExerciseDeepDiveInput {
    /// Produces a plain-text serialisation suitable for use as the user-turn prompt
    /// in a `LanguageModelSession`.
    func toPromptText() -> String {
        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Exercise: \(exerciseName)")
        lines.append("Total sessions analysed: \(totalSessions)")
        lines.append("History range: \(historyRange)")
        lines.append("")
        lines.append("Overall progression (first → most recent session):")
        let deltaSign = overallProgression.estimatedOneRMDeltaKg >= 0 ? "+" : ""
        lines.append("  Estimated 1RM delta: \(deltaSign)\(String(format: "%.1f", overallProgression.estimatedOneRMDeltaKg)) kg")
        lines.append("  Percent change: \(overallProgression.percentChange >= 0 ? "+" : "")\(overallProgression.percentChange)%")
        lines.append("")
        lines.append("All-time peak performance:")
        lines.append("  Weight: \(String(format: "%.1f", peak.weightKg)) kg × \(peak.reps) reps")
        lines.append("  Estimated 1RM: \(String(format: "%.1f", peak.estimatedOneRMKg)) kg")
        lines.append("  When: \(peak.monthLabel)")
        lines.append("")
        lines.append("Strongest improvement segment:")
        lines.append("  Period: \(strongestSegment.range)")
        lines.append("  Classification: \(strongestSegment.classification)")
        lines.append("  Change: \(strongestSegment.magnitude)")
        lines.append("  Avg sessions/week: \(String(format: "%.1f", strongestSegment.avgSessionsPerWeek))")
        lines.append("")
        lines.append("Current segment (last 4–8 weeks):")
        lines.append("  Period: \(currentSegment.range)")
        lines.append("  Classification: \(currentSegment.classification)")
        lines.append("  Change: \(currentSegment.magnitude)")
        lines.append("  Avg sessions/week: \(String(format: "%.1f", currentSegment.avgSessionsPerWeek))")
        return lines.joined(separator: "\n")
    }
}
