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

    @Guide(description: "Training regularity metrics for the period")
    let consistency: ConsistencyMetrics

    @Guide(description: "Top trends across exercises or muscle groups, maximum 5 entries")
    let trends: [TrendFinding]

    @Guide(description: "Correlation findings between training habits and outcomes")
    let correlations: [CorrelationFinding]

    @Guide(description: "Pre-resolved actionable recommendation, nil when none was detected")
    let recommendationFact: String?

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
struct ConsistencyMetrics {
    @Guide(description: "Number of calendar weeks the period covers so far")
    let totalWeeks: Int

    @Guide(description: "Number of those weeks with at least one session")
    let trainedWeeks: Int

    @Guide(description: "Average number of sessions per week")
    let averageSessionsPerWeek: Double

    @Guide(description: "Longest gap between two consecutive sessions in days")
    let longestGapDays: Int

    @Guide(description: "Whether training was irregular (skipped weeks or long gaps)")
    let isIrregular: Bool
}

@Generable
struct TrendFinding {
    @Guide(description: "The exercise name or muscle group this trend applies to")
    let subject: String

    @Guide(description: "Direction of the trend: 'improved', 'plateaued', 'regressed', or 'mixed'")
    let direction: String

    @Guide(description: "Signed estimated-1RM change over the period, e.g. '+8.5 kg'")
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
    /// in a `LanguageModelSession`. Every fact the model may state — the headline
    /// story, the trend groups, and the closing takeaway — is resolved here in
    /// Swift; the model only rephrases the fact lines in the user's language.
    func toPromptText() -> String {
        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Period: \(periodLabel)")

        if isInsufficient {
            lines.append("Insufficient data: only \(headline.totalSessions) session(s) — fewer than 3. Output brief encouragement, no analysis.")
            return lines.joined(separator: "\n")
        }

        let improved = trends.filter { $0.direction == "improved" }
        let plateaued = trends.filter { $0.direction == "plateaued" }
        let regressed = trends.filter { $0.direction == "regressed" }

        lines.append("Headline fact: \(headlineFact(improved: improved, plateaued: plateaued, regressed: regressed))")
        if let recommendationFact {
            lines.append("Closing fact (a concrete recommendation — phrase as a suggestion): \(recommendationFact)")
        } else {
            lines.append("Closing fact: \(closingFact(improved: improved, plateaued: plateaued, regressed: regressed))")
        }
        lines.append("")
        lines.append("Sessions: \(headline.totalSessions), average \(headline.averageSessionMinutes) min, \(headline.distinctExercises) distinct exercises")

        var consistencyLine = "Consistency: trained in \(consistency.trainedWeeks) of \(consistency.totalWeeks) weeks, on average \(String(format: "%.1f", consistency.averageSessionsPerWeek)) sessions per week"
        if consistency.longestGapDays > 0 {
            consistencyLine += ", longest gap \(consistency.longestGapDays) days"
        }
        consistencyLine += consistency.isIrregular ? " — irregular" : " — regular"
        lines.append(consistencyLine)

        if !improved.isEmpty {
            lines.append("Improved (estimated 1RM): " + improved.map { "\($0.subject) \($0.magnitude)" }.joined(separator: ", "))
        }
        if !regressed.isEmpty {
            lines.append("Declined (estimated 1RM): " + regressed.map { "\($0.subject) \($0.magnitude)" }.joined(separator: ", "))
        }
        if !plateaued.isEmpty {
            lines.append("Unchanged (plateau): " + plateaued.map(\.subject).joined(separator: ", "))
        }

        if !correlations.isEmpty {
            lines.append("")
            lines.append("Detected patterns:")
            for c in correlations {
                lines.append("  - \(c.statement)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Fact Resolution

    /// The single most important story of the period, in priority order:
    /// strongest gain > declines > steady plateau > no measurable trends.
    private func headlineFact(
        improved: [TrendFinding],
        plateaued: [TrendFinding],
        regressed: [TrendFinding]
    ) -> String {
        if let top = improved.first {
            var fact = "strongest gain: \(top.subject) \(top.magnitude) estimated 1RM"
            if improved.count > 1 {
                fact += " (\(improved.count) exercises improved in total)"
            }
            return fact
        }
        if !regressed.isEmpty {
            return plateaued.isEmpty
                ? "no gains this period: \(regressed.count) exercise(s) declined"
                : "no gains this period: \(plateaued.count) exercise(s) unchanged, \(regressed.count) declined"
        }
        if !plateaued.isEmpty {
            return "strength held steady across all \(plateaued.count) tracked exercises"
        }
        return "not enough repeated exercises to measure strength trends"
    }

    /// The forward-looking takeaway used when no recommendation was resolved.
    private func closingFact(
        improved: [TrendFinding],
        plateaued: [TrendFinding],
        regressed: [TrendFinding]
    ) -> String {
        if !regressed.isEmpty {
            return "worth watching: \(regressed.map(\.subject).joined(separator: ", ")) declined this period"
        }
        if !plateaued.isEmpty {
            return "\(plateaued.map(\.subject).prefix(3).joined(separator: ", ")) stayed unchanged the whole period"
        }
        if !improved.isEmpty {
            return "all tracked exercises are trending upward"
        }
        return "more sessions will make the next recap more meaningful"
    }
}
