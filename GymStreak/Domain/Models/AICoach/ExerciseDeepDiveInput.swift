//
//  ExerciseDeepDiveInput.swift
//  GymStreak
//

import Foundation
import FoundationModels

/// The usage the exercise detail screen is showing, as the deep-dive needs it.
///
/// The two halves travel together because they have to agree: the **selection** decides
/// which history rows the narrative describes and keys its cache, and the **label** is
/// what the narrative calls that variant. Resolving the label separately is how the coach
/// would come to name a variant differently from the menu the user picked it in — the
/// picker renders `ExerciseUsageLabeling.pickerItems`, which prepends the archived marker
/// and appends a disambiguator where two usages would otherwise read alike, so
/// `ExerciseUsage.displayLabel` alone is *not* the picker's label.
struct DeepDiveUsage: Equatable, Sendable {
    let selection: ExerciseUsageSelection
    /// Exactly the string the picker shows — `ExerciseProgressViewModel.selectedUsageLabel`.
    /// `nil` for `.combined`, which names no single variant.
    let label: String?

    /// Every usage folded together: the whole exercise, and the only shape an exercise
    /// trained exactly one way ever has.
    static let combined = DeepDiveUsage(selection: .combined, label: nil)

    init(selection: ExerciseUsageSelection, label: String?) {
        self.selection = selection
        // A label belongs to a variant. Dropped here rather than trusted from callers,
        // so `.combined` can never be narrated as "the 4–6 reps · Pull variant" — the
        // view model's `selectedUsageLabel` returns "Alle Varianten" for it.
        self.label = selection == .combined ? nil : label
    }
}

@Generable
struct ExerciseDeepDiveInput {
    @Guide(description: "User's locale identifier, e.g. 'de_DE' or 'en_US'")
    let locale: String

    @Guide(description: "Name of the exercise being analyzed")
    let exerciseName: String

    /// The usage the screen is showing, named exactly as the picker names it — "4–6 reps · Pull".
    /// `nil` when the analysis covers every usage there is (one usage, or the combined view).
    ///
    /// **Its presence is what reaches the model, never its content.** `toPromptText()`
    /// emits a `Variant:` line when this is non-`nil` and deliberately withholds the
    /// string: asked to name the variant, the on-device model expanded `4–6 Wdh. · Pull`
    /// into "die 4-6-Woche-Biceps-Curls-Variante" — reading the German abbreviation for
    /// *Wiederholungen* as *Woche*. The reader sees the label rendered exactly, by
    /// `CoachDeepDiveSurface`'s caption. Do not hand a language model a string you need it
    /// to reproduce verbatim.
    // The guide deliberately carries no example of the label: this field's content must
    // never reach a model, and a worked example is exactly how it would if this input
    // ever moved to structured `@Generable` prompting.
    @Guide(description: "Present when the analysis describes one specific variant rather than the whole exercise. Its value is rendered to the reader and must not be used in generated text")
    let usageLabel: String?

    /// How many distinct usages the described body of work folds together. `1` for a
    /// selected usage — and for a combined view of an exercise trained exactly one way,
    /// where combined *is* that usage. Greater than 1 only for a genuinely blended view,
    /// which is the case where every progression figure below is withheld.
    @Guide(description: "Number of distinct training variants folded into this analysis. 1 unless the view deliberately blends several")
    let blendedUsageCount: Int

    @Guide(description: "Total number of sessions in which this exercise was performed")
    let totalSessions: Int

    @Guide(description: "Date range of recorded history for this exercise, e.g. '2024-05 to 2026-04'")
    let historyRange: String

    /// `nil` when `blendedUsageCount > 1`: a first-to-last comparison across several
    /// usages measures which usage happened to fall at each end of the range, not
    /// progress. Withheld rather than stated — the same rule the Trend stat card applies
    /// when it prints *Gemischt* (`docs/progress-charts.md`).
    @Guide(description: "Overall progression from first to most recent session. Absent when the analysis blends several variants")
    let overallProgression: ProgressionSummary?

    @Guide(description: "The single best performance point across all history")
    let peak: PerformancePoint

    /// `nil` for the same reason as `overallProgression`: a segment's magnitude is a
    /// first-to-last delta too.
    @Guide(description: "The strongest improvement segment found in the history. Absent when the analysis blends several variants")
    let strongestSegment: ProgressionSegment?

    @Guide(description: "The most recent 4–8 week segment of training. Absent when the analysis blends several variants")
    let currentSegment: ProgressionSegment?
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
    ///
    /// **A blended view emits no progression figures at all** — not a hedged one, not a
    /// labelled one. The model is told the figure is unavailable and why, because the
    /// only reliable way to stop a language model stating a number is to not give it the
    /// number.
    func toPromptText() -> String {
        // Numbers are written in the reader's own convention here — "20,0" for a German
        // reader, "20.0" for an English one — so the model only ever copies them. Asking
        // it to convert separators would be one more transformation it can get wrong, and
        // a coach writing "20.0 kg" beside a UI that says "44,1 lb" reads as foreign.
        let readerLocale = Locale(identifier: locale)
        func decimal(_ value: Double) -> String {
            String(format: "%.1f", locale: readerLocale, value)
        }

        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Exercise: \(exerciseName)")
        if usageLabel != nil {
            // The label itself is withheld on purpose — see `usageLabel`. Only the fact
            // that one specific variant is being described crosses into the prompt.
            lines.append("Variant: one specific variant of this exercise. Its label is already shown to the reader above your text; do not restate, translate or expand it.")
            lines.append("Every figure below describes only this variant of the exercise.")
        }
        lines.append("Total sessions analysed: \(totalSessions)")
        // The reader's complete history for what is being described — never the range
        // selected on the chart above, which is usually shorter. Localized month names,
        // because the machine format `2026-07 to 2026-08` came back echoed verbatim.
        lines.append("History range (the reader's complete history, not the chart's selected range): \(historyRange)")
        lines.append("")

        if blendedUsageCount > 1 {
            lines.append("BLENDED VIEW: this analysis folds \(blendedUsageCount) different variants of this exercise together (different routine slots, different rep-range goals).")
            lines.append("No progression figure is available for it, and none may be stated or inferred: comparing the first session with the most recent one across several variants measures which variant happened to fall at each end of the range, not progress.")
        } else {
            if let overallProgression {
                lines.append("Overall progression (first → most recent session):")
                let deltaSign = overallProgression.estimatedOneRMDeltaKg >= 0 ? "+" : ""
                lines.append("  Estimated 1RM delta: \(deltaSign)\(decimal(overallProgression.estimatedOneRMDeltaKg)) kg")
                lines.append("  Percent change: \(overallProgression.percentChange >= 0 ? "+" : "")\(overallProgression.percentChange)%")
                lines.append("")
            }
        }

        lines.append("All-time peak performance:")
        lines.append("  Weight: \(decimal(peak.weightKg)) kg × \(peak.reps) reps")
        lines.append("  Estimated 1RM: \(decimal(peak.estimatedOneRMKg)) kg")
        lines.append("  When: \(peak.monthLabel)")

        if let strongestSegment {
            lines.append("")
            lines.append("Strongest improvement segment:")
            lines.append("  Period: \(strongestSegment.range)")
            lines.append("  Classification: \(strongestSegment.classification)")
            lines.append("  Change: \(strongestSegment.magnitude)")
            lines.append("  Avg sessions/week: \(decimal(strongestSegment.avgSessionsPerWeek))")
        }
        if let currentSegment {
            lines.append("")
            lines.append("Current segment (last 4–8 weeks):")
            lines.append("  Period: \(currentSegment.range)")
            lines.append("  Classification: \(currentSegment.classification)")
            lines.append("  Change: \(currentSegment.magnitude)")
            lines.append("  Avg sessions/week: \(decimal(currentSegment.avgSessionsPerWeek))")
        }
        return lines.joined(separator: "\n")
    }
}
