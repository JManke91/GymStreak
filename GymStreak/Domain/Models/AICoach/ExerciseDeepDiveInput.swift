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
// `Sendable` is explicit rather than inferred: this value crosses off the History model
// actor as half of `ExerciseDeepDiveAggregate` (ticket 02), so a future non-`Sendable`
// stored property must fail the build here rather than silently withdraw the guarantee.
struct ExerciseDeepDiveInput: Sendable {
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

    @Guide(description: "Date range of recorded history for this exercise, in localized month names, e.g. 'May 2024 – April 2026'")
    let historyRange: String

    /// `nil` when `blendedUsageCount > 1`: a first-to-last comparison across several
    /// usages measures which usage happened to fall at each end of the range, not
    /// progress. Withheld rather than stated — the same rule the Trend stat card applies
    /// when it prints *Gemischt* (`docs/progress-charts.md`).
    @Guide(description: "Overall progression from first to most recent session. Absent when the analysis blends several variants")
    let overallProgression: ProgressionSummary?

    /// **Rendered, never narrated.** `toPromptText()` emits nothing from this — the
    /// figures and the month are composed into `peakSentence` in Swift and drawn by
    /// `CoachDeepDiveSurface`. It is here because it is a fact of the described body of
    /// work, not because a model is meant to see it.
    @Guide(description: "The single best performance point across all history. Rendered to the reader and never used in generated text")
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

    // Already rendered — by `ExerciseDeepDiveAggregator`, in the reader's unit and their
    // decimal convention — so this example names no unit: the value is "+5.0 kg est. 1RM"
    // for one reader and "+11.0 lb est. 1RM" for the next.
    @Guide(description: "Human-readable magnitude of change during this segment, already carrying its weight unit, or 'stable'")
    let magnitude: String
}

// MARK: - Prompt Serialisation

extension ExerciseDeepDiveInput {

    /// One figure, written in the reader's own convention — "20,0" for a German reader,
    /// "20.0" for an English one — so the model only ever copies it. Asking it to convert
    /// separators would be one more transformation it can get wrong, and a coach writing
    /// "20.0 kg" beside a UI that says "44,1 lb" reads as foreign.
    ///
    /// Takes **canonical kilograms** and converts, like every other figure this type
    /// writes — see `toPromptText(in:)`.
    private func decimal(_ kilograms: Double, in unit: WeightUnit) -> String {
        AICoachUnitVocabulary.decimal(kilograms, in: unit, locale: Locale(identifier: locale))
    }

    /// A frequency, not a weight — same reader convention, no conversion.
    private func sessionsPerWeek(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: locale), value)
    }

    /// The all-time peak as one finished sentence in the reader's language — **composed
    /// here, never generated**.
    ///
    /// The peak used to reach the model as labelled facts, month included, and the model
    /// decorated the month into a day: *"erreicht am 20.08.2026"* for an input whose only
    /// date was `August 2026`, with the "20" lifted from the `20,0 kg` beside it. Three
    /// rounds of "never state a date more precise than the input gives" did not stop it.
    /// A month is a date a language model can make more precise, so no month reaches one:
    /// `toPromptText()` emits no peak at all and `CoachDeepDiveSurface` renders this
    /// sentence directly, the same move that fixed the variant label.
    ///
    /// The localized template is resolved from the app's language rather than `locale`,
    /// which is what every other user-facing string on this screen does — the two agree
    /// because `locale` is the reader's current locale.
    ///
    /// **App-authored copy, so it reads in the reader's unit.** It is drawn directly
    /// under a chart headline that already says `44,1 lb`; left in kilograms it read as
    /// the app contradicting itself, which is why this — one `String` and one strings
    /// key — was the cheapest site in the whole unit conversion. Both figures are handed
    /// to the template preformatted, via `AICoachUnitVocabulary.labelled`, per the `%@`
    /// pattern `docs/weight-unit-preference.md` §7 makes binding.
    func peakSentence(in unit: WeightUnit) -> String {
        let readerLocale = Locale(identifier: locale)
        return "ai_coach.deep_dive.peak".localized(
            AICoachUnitVocabulary.labelled(peak.weightKg, in: unit, locale: readerLocale),
            peak.reps,
            AICoachUnitVocabulary.labelled(peak.estimatedOneRMKg, in: unit, locale: readerLocale),
            peak.monthLabel
        )
    }

    /// Produces a plain-text serialisation suitable for use as the user-turn prompt
    /// in a `LanguageModelSession`.
    ///
    /// **A blended view emits no progression figures at all** — not a hedged one, not a
    /// labelled one. The model is told the figure is unavailable and why, because the
    /// only reliable way to stop a language model stating a number is to not give it the
    /// number. **No peak reaches it either**, for the same reason — see `peakSentence`.
    ///
    /// **This is the conversion boundary for the one weight it does emit.**
    /// `estimatedOneRMDeltaKg` stays canonical kilograms in the DTO — the aggregator's
    /// kilogram-magnitude "is this worth mentioning" thresholds are applied to it before
    /// anything converts — and it is converted here, once, as it becomes text. The
    /// segment magnitudes arrive already rendered in this unit from
    /// `ExerciseDeepDiveAggregator`, which is where those strings are made.
    /// See docs/weight-unit-preference.md §13.
    func toPromptText(in unit: WeightUnit) -> String {
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
                // Labelled as a change, and explicitly as the *only* thing available.
                // `Overall progression (first → most recent session):` named two endpoints
                // the input does not carry, and the model supplied them: it wrote "von
                // 87,5 kg im ersten Training auf 88,2 kg im letzten Training" — the 87,5
                // lifted from a worked example in the instructions, the 88,2 derived by
                // adding this real delta to it. Never describe a shape that presupposes
                // data the prompt does not hold.
                lines.append("Overall progression across the whole history — a change only; no starting or ending 1RM value is available:")
                let deltaSign = overallProgression.estimatedOneRMDeltaKg >= 0 ? "+" : ""
                lines.append("  Estimated 1RM change: \(deltaSign)\(decimal(overallProgression.estimatedOneRMDeltaKg, in: unit)) \(AICoachUnitVocabulary.unitWord(unit))")
                lines.append("  Percent change: \(overallProgression.percentChange >= 0 ? "+" : "")\(overallProgression.percentChange)%")
                lines.append("")
            }
        }

        if let strongestSegment {
            lines.append("Strongest improvement segment:")
            lines.append("  Period: \(strongestSegment.range)")
            lines.append("  Classification: \(strongestSegment.classification)")
            lines.append("  Change: \(strongestSegment.magnitude)")
            // Spelled out, not left as a bare ratio under an `Avg sessions/week` label:
            // handed `1.3` under that label the model wrote "1,3 Wochen pro Sitzung" —
            // the ratio inverted. It now has the phrase to copy rather than a direction
            // to work out.
            lines.append("  Training frequency: \(sessionsPerWeek(strongestSegment.avgSessionsPerWeek)) sessions per week")
        }
        if let currentSegment {
            lines.append("")
            // Labelled without its window. It used to read `Current segment (last 4–8
            // weeks):` and the model copied the label into prose — "in den letzten 4–8
            // Wochen" — presenting the app's own bucketing parameter to the reader as a
            // period. The `Period:` line below carries the real range.
            lines.append("Recent segment:")
            lines.append("  Period: \(currentSegment.range)")
            lines.append("  Classification: \(currentSegment.classification)")
            lines.append("  Change: \(currentSegment.magnitude)")
            lines.append("  Training frequency: \(sessionsPerWeek(currentSegment.avgSessionsPerWeek)) sessions per week")
        }
        return lines.joined(separator: "\n")
    }
}
