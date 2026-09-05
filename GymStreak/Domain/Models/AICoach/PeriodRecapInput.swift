//
//  PeriodRecapInput.swift
//  GymStreak
//

import Foundation
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

    /// **This guide names no programming construct**, and none may be added, even though
    /// nothing sends an input's schema to a model today — `AICoachService` sends an input
    /// only as `toPromptText(...)`. It used to read *"nil when none was detected"*, which
    /// is the exact wording that made the model write a literal `nil` into
    /// `PeriodRecapOutput.correlationHighlight`; a guide is prompt text, so the word is
    /// something to write, not an absence to produce. Left as it was, this was that bug
    /// pre-made for the first time this type is used as a generation *output*. See
    /// docs/ai-coach.md § "Prompt grounding rules", rule 3.
    @Guide(description: "Pre-resolved actionable recommendation. This field is left out entirely when no recommendation was detected.")
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

    // Already rendered — by `PeriodRecapAggregator`, in the reader's unit — so this
    // example names no unit: the value is "+8.5 kg" for one reader and "+18.7 lb"
    // for the next. The prompt emits it verbatim; nothing here converts.
    @Guide(description: "Signed estimated-1RM change over the period, already carrying its weight unit")
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

        // Reader's separator — the prompt has the model copy figures verbatim.
        var consistencyLine = "Consistency: trained in \(consistency.trainedWeeks) of \(consistency.totalWeeks) weeks, on average \(AICoachUnitVocabulary.plainDecimal(consistency.averageSessionsPerWeek, locale: Locale(identifier: locale))) sessions per week"
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
    ///
    /// **The gain fact names one exercise and stops there.** It used to append
    /// `" (N exercises improved in total)"`, and the model translated the parenthetical
    /// only halfway: *"(4 Übungen verbessert in total)"* (German, on device, 2026-08-30).
    /// A parenthetical aside reads as finished copy rather than as a fact to rephrase, so
    /// the model copies part of it instead of writing the sentence itself. The count was
    /// never exclusive to it either — the "Improved (estimated 1RM):" line below lists
    /// every improved exercise by name, which is what `trendsNarrative` is built from.
    private func headlineFact(
        improved: [TrendFinding],
        plateaued: [TrendFinding],
        regressed: [TrendFinding]
    ) -> String {
        if let top = improved.first {
            return "strongest gain: \(top.subject) \(top.magnitude) estimated 1RM"
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
