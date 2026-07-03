//
//  PeriodRecapInput.swift
//  GymStreak
//

import FoundationModels

@Generable
struct PeriodRecapInput {
    @Guide(description: "User's locale identifier, e.g. 'de_DE' or 'en_US'")
    let locale: String

    @Guide(description: "Human-readable label for the period, e.g. 'April 2026' or 'This Week'")
    let periodLabel: String

    @Guide(description: "Headline aggregate metrics for the period")
    let headline: HeadlineMetrics

    @Guide(description: "Top trends across exercises or muscle groups, maximum 5 entries")
    let trends: [TrendFinding]

    @Guide(description: "Correlation findings between training habits and outcomes")
    let correlations: [CorrelationFinding]

    @Guide(description: "True when there are fewer than 3 sessions in the period — model should respond with encouragement rather than analysis")
    let isInsufficient: Bool
}

@Generable
struct HeadlineMetrics {
    @Guide(description: "Total number of completed workout sessions in the period")
    let totalSessions: Int

    @Guide(description: "Total training volume across all sessions in kilograms")
    let totalVolumeKg: Double

    @Guide(description: "Average duration of a session in minutes")
    let averageSessionMinutes: Int

    @Guide(description: "Number of distinct exercises performed in the period")
    let distinctExercises: Int
}

@Generable
struct TrendFinding {
    @Guide(description: "The exercise name or muscle group this trend applies to")
    let subject: String

    @Guide(description: "Direction of the trend: 'improved', 'plateaued', 'regressed', or 'mixed'")
    let direction: String

    @Guide(description: "Human-readable magnitude of the trend, e.g. '+8.5kg estimated 1RM' or '+12% volume'")
    let magnitude: String
}

@Generable
struct CorrelationFinding {
    @Guide(description: "Plain-language description of the correlation, already in the user's language")
    let statement: String
}

// MARK: - Prompt Serialisation

extension PeriodRecapInput {
    /// Produces a plain-text serialisation suitable for use as the user-turn prompt
    /// in a `LanguageModelSession`.
    func toPromptText() -> String {
        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Period: \(periodLabel)")
        lines.append("Insufficient data (fewer than 3 sessions): \(isInsufficient ? "yes" : "no")")
        lines.append("")
        lines.append("Headline metrics:")
        lines.append("  Total sessions: \(headline.totalSessions)")
        lines.append("  Total volume: \(String(format: "%.1f", headline.totalVolumeKg)) kg")
        lines.append("  Average session duration: \(headline.averageSessionMinutes) min")
        lines.append("  Distinct exercises: \(headline.distinctExercises)")
        if !trends.isEmpty {
            lines.append("")
            lines.append("Exercise trends (most significant first):")
            for t in trends {
                lines.append("  - \(t.subject): \(t.direction), \(t.magnitude)")
            }
        }
        if !correlations.isEmpty {
            lines.append("")
            lines.append("Training correlations:")
            for c in correlations {
                lines.append("  - \(c.statement)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
