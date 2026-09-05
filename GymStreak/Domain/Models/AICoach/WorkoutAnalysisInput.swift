//
//  WorkoutAnalysisInput.swift
//  GymStreak
//
//  Input struct for the workout detail AI Coach analysis surface.
//  Compares a completed workout session against the previous session
//  of the same routine.
//

import Foundation
import FoundationModels

@Generable
struct WorkoutAnalysisInput {
    @Guide(description: "User's locale identifier, e.g. 'de_DE' or 'en_US'")
    let locale: String

    @Guide(description: "Name of the routine, e.g. 'Push Day' or 'Upper Body'")
    let routineName: String

    @Guide(description: "Days elapsed between the previous and the current session")
    let daysSincePrevious: Int

    @Guide(description: "Duration of the current workout in minutes")
    let currentDurationMinutes: Int

    @Guide(description: "Total number of completed sets in the current workout")
    let currentTotalSets: Int

    @Guide(description: "Completion percentage of the current workout (0-100)")
    let currentCompletionPercentage: Int

    @Guide(description: "Total number of completed sets in the previous session")
    let previousTotalSets: Int

    @Guide(description: "Number of exercises done in the previous session but skipped this time")
    let droppedExerciseCount: Int

    @Guide(description: "Per-exercise comparison data for each exercise in this workout")
    let exercises: [WorkoutAnalysisExerciseInput]

    @Guide(description: "New personal records achieved in this session")
    let newPRs: [PRSummary]
}

@Generable
struct WorkoutAnalysisExerciseInput {
    @Guide(description: "Name of the exercise")
    let exerciseName: String

    @Guide(description: "Whether this is the first time performing this exercise (no previous data)")
    let isFirstTime: Bool

    @Guide(description: "Per-set comparison details")
    let sets: [WorkoutAnalysisSetInput]
}

@Generable
struct WorkoutAnalysisSetInput {
    @Guide(description: "Set number (1-based)")
    let setNumber: Int

    @Guide(description: "Weight used in kilograms")
    let currentWeightKg: Double

    @Guide(description: "Reps performed")
    let currentReps: Int

    @Guide(description: "Whether this set was completed")
    let isCompleted: Bool

    /// Neither optional's guide names a programming construct — see
    /// `PeriodRecapInput.recommendationFact` for the failure that rule comes from.
    @Guide(description: "Previous weight for this set number in kilograms. This field is left out entirely when there is no previous data for the set.")
    let previousWeightKg: Double?

    @Guide(description: "Previous reps for this set number. This field is left out entirely when there is no previous data for the set.")
    let previousReps: Int?
}

// MARK: - Headline Story

/// The single most important story of a session, classified in Swift.
///
/// **The headline is composed, never generated** — see `WorkoutAnalysisInput.headlineSentence`.
/// Modelling it as a case rather than a string keeps the prompt's English context line and
/// the reader's localized sentence two renderings of one decision.
enum WorkoutAnalysisHeadline: Equatable {
    /// `additionalCount` is the number of *further* PRs beyond the one named.
    case personalRecord(exerciseName: String, weightKg: Double, reps: Int, additionalCount: Int)
    case allImproved(total: Int)
    case someImproved(improved: Int, total: Int)
    case allDeclined(total: Int)
    case someDeclined(declined: Int, total: Int)
    case allUnchanged(total: Int)
    case mixed(improved: Int, declined: Int, swings: Int)
    /// Every exercise carried a `NEW SETS` verdict — nothing to compare.
    case noComparableData
}

// MARK: - Prompt Serialisation

extension WorkoutAnalysisInput {
    /// Completion percentage below which the prompt flags the session as cut short.
    static let cutShortThreshold = 70

    /// Produces a plain-text serialisation suitable for use as the user-turn prompt
    /// in a `LanguageModelSession`. Every fact the model may state — the headline
    /// story and each exercise's concrete change — is resolved here in Swift.
    /// The on-device model's only job is rephrasing the fact lines in the
    /// user's language; it never sees raw per-set numbers to compose from.
    ///
    /// **This is the conversion boundary.** `currentWeightKg` / `previousWeightKg` /
    /// `PRSummary.weightKg` stay canonical kilograms — the deltas and the top-set
    /// comparison below are computed on them — and each figure is converted once, as
    /// it is written into a fact line. See docs/weight-unit-preference.md §13.
    ///
    /// - Parameter unit: the reader's unit. `WorkoutAnalysisInstructions` must be built
    ///   with the same one; its German example patterns spell the unit out.
    func toPromptText(in unit: WeightUnit) -> String {
        // The fact lines' words are English and get translated; their figures are copied
        // verbatim, so every figure below carries the reader's decimal separator. See
        // docs/ai-coach.md § "Prompt grounding rules", rule 1.
        let readerLocale = Locale(identifier: locale)
        // First-time exercises have no baseline: they never become highlights,
        // only a closing-observation note.
        let comparableExercises = exercises.filter { !$0.isFirstTime }
        let firstTimeNames = exercises.filter(\.isFirstTime).map(\.exerciseName)
        let verdicts = comparableExercises.map { Self.exerciseVerdict($0, in: unit, locale: readerLocale) }

        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Routine: \(routineName)")
        lines.append("Current session: \(currentTotalSets) sets, \(currentDurationMinutes) min")
        lines.append("Previous session (\(daysSincePrevious) days earlier): \(previousTotalSets) sets")
        // Context for the closing sentence only — the headline itself is composed in
        // Swift (`headlineSentence`) and never generated, so nothing here is rendered
        // verbatim. The exercise name in a PR story still crosses over because the PR
        // highlight has to state that set.
        lines.append("Session summary: \(Self.promptFact(for: headlineStory(verdicts: verdicts), in: unit, locale: readerLocale))")

        if currentCompletionPercentage < Self.cutShortThreshold {
            lines.append("Note: the workout was cut short — only \(currentCompletionPercentage)% of the planned sets were completed. Missing sets are not lost strength.")
        }
        if droppedExerciseCount > 0 {
            lines.append("Note: \(droppedExerciseCount) exercise(s) from the last session were skipped this time.")
        }
        if !firstTimeNames.isEmpty {
            lines.append("Note: done for the first time, no comparison possible: \(firstTimeNames.joined(separator: ", ")).")
        }
        lines.append("")

        for (exercise, verdict) in zip(comparableExercises, verdicts) {
            lines.append("\(exercise.exerciseName) [\(verdict.label)]")
            lines.append("  Fact: \(verdict.fact)")
        }

        if !newPRs.isEmpty {
            lines.append("")
            lines.append("New PRs:")
            for pr in newPRs {
                lines.append("- \(pr.exerciseName): \(Self.fmt(pr.weightKg, in: unit, locale: readerLocale)) \(AICoachUnitVocabulary.unitWord(unit)) x \(pr.reps) reps")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Headline Story

    /// The session's headline as the reader sees it — **composed here, never generated**.
    ///
    /// It used to be a `headline` field on `WorkoutAnalysisOutput`: the prompt stated the
    /// fact and the model rephrased it. On a device check that produced *"Neuer Bestwert
    /// bei Bankdrücken: 16 kg x 7 Wiederholungen"* for a session in which Bankdrücken was
    /// not trained at all — the numbers belonged to Dip, and the name was lifted from the
    /// worked example in the instructions, pulled in by the same prompt's "translate every
    /// word into the target language" rule, which an English exercise name reads as an
    /// invitation. Two independent fixes followed: exercise names are now carved out of
    /// that translation rule and no exercise name appears in an example (see
    /// `WorkoutAnalysisInstructions`), and this sentence no longer passes through the
    /// model at all. Only the second one cannot be undone by the next prompt edit —
    /// nothing can mangle a string it never receives, the same move as
    /// `ExerciseDeepDiveInput.peakSentence`.
    ///
    /// The localized template is resolved from the app's language rather than `locale`,
    /// which is what every other user-facing string on this screen does — the two agree
    /// because `locale` is the reader's current locale.
    ///
    /// **App-authored copy, so it reads in the reader's unit.** It sits directly above
    /// the model's paragraphs and beside converted figures elsewhere on the screen; a
    /// kilogram headline over a pound analysis reads as the app contradicting itself.
    /// The weight is handed to the localized template preformatted, via
    /// `AICoachUnitVocabulary.labelled` — the `%@` pattern
    /// `docs/weight-unit-preference.md` §7 makes binding.
    ///
    /// - Parameter unit: the reader's unit, from the same preference the surrounding
    ///   screen renders with.
    func headlineSentence(in unit: WeightUnit) -> String {
        let readerLocale = Locale(identifier: locale)
        let comparable = exercises.filter { !$0.isFirstTime }
        return Self.localizedSentence(
            for: headlineStory(verdicts: comparable.map {
                Self.exerciseVerdict($0, in: unit, locale: readerLocale)
            }),
            locale: readerLocale,
            unit: unit
        )
    }

    /// Resolves the single most important story of the session, in priority order:
    /// new PR > all/majority improved > all/majority declined > unchanged > mixed.
    private func headlineStory(verdicts: [ExerciseVerdict]) -> WorkoutAnalysisHeadline {
        if let pr = newPRs.first {
            return .personalRecord(
                exerciseName: pr.exerciseName,
                weightKg: pr.weightKg,
                reps: pr.reps,
                additionalCount: newPRs.count - 1
            )
        }

        let comparableLabels: Set<String> = ["IMPROVED", "DECREASED", "MIXED", "UNCHANGED"]
        let comparable = verdicts.filter { comparableLabels.contains($0.label) }
        let improved = comparable.filter { $0.label == "IMPROVED" }.count
        let declined = comparable.filter { $0.label == "DECREASED" }.count
        let mixed = comparable.filter { $0.label == "MIXED" }.count
        let total = comparable.count

        guard total > 0 else { return .noComparableData }
        if improved > 0 && declined == 0 && mixed == 0 {
            return improved == total ? .allImproved(total: total) : .someImproved(improved: improved, total: total)
        }
        if declined > 0 && improved == 0 && mixed == 0 {
            return declined == total ? .allDeclined(total: total) : .someDeclined(declined: declined, total: total)
        }
        if improved == 0 && declined == 0 && mixed == 0 {
            return .allUnchanged(total: total)
        }
        return .mixed(improved: improved, declined: declined, swings: mixed)
    }

    /// The English rendering that reaches the prompt as context for the closing sentence.
    private static func promptFact(for headline: WorkoutAnalysisHeadline, in unit: WeightUnit, locale: Locale) -> String {
        switch headline {
        case let .personalRecord(name, weightKg, reps, additionalCount):
            var fact = "new personal record on \(name): \(fmt(weightKg, in: unit, locale: locale)) \(AICoachUnitVocabulary.unitWord(unit)) x \(reps) reps"
            if additionalCount > 0 {
                fact += " (and \(additionalCount) more PRs)"
            }
            return fact
        case let .allImproved(total):
            return "all \(total) exercises improved vs last session"
        case let .someImproved(improved, total):
            return "\(improved) of \(total) exercises improved, the rest unchanged"
        case let .allDeclined(total):
            return "all \(total) exercises below last session"
        case let .someDeclined(declined, total):
            return "\(declined) of \(total) exercises below last session, the rest unchanged"
        case let .allUnchanged(total):
            return "same weights and reps as last session across all \(total) exercises"
        case let .mixed(improved, declined, swings):
            var fact = "mixed session: \(improved) improved, \(declined) declined"
            if swings > 0 {
                fact += ", \(swings) up and down"
            }
            return fact
        case .noComparableData:
            return "first comparable session — no previous exercise data"
        }
    }

    /// The reader's rendering, in the app's language.
    private static func localizedSentence(
        for headline: WorkoutAnalysisHeadline,
        locale: Locale,
        unit: WeightUnit
    ) -> String {
        let key = "ai_coach.workout_analysis.headline."
        switch headline {
        case let .personalRecord(name, weightKg, reps, additionalCount):
            return additionalCount > 0
                ? (key + "pr_multiple").localized(name, weightLabel(weightKg, in: unit, locale: locale), reps, additionalCount)
                : (key + "pr").localized(name, weightLabel(weightKg, in: unit, locale: locale), reps)
        case let .allImproved(total):
            return total == 1
                ? (key + "one_improved").localized
                : (key + "all_improved").localized(total)
        case let .someImproved(improved, total):
            return (key + "some_improved").localized(improved, total)
        case let .allDeclined(total):
            return total == 1
                ? (key + "one_declined").localized
                : (key + "all_declined").localized(total)
        case let .someDeclined(declined, total):
            return (key + "some_declined").localized(declined, total)
        case .allUnchanged:
            return (key + "unchanged").localized
        case let .mixed(improved, declined, swings):
            return swings > 0
                ? (key + "mixed_with_swings").localized(improved, declined, swings)
                : (key + "mixed").localized(improved, declined)
        case .noComparableData:
            return (key + "no_comparison").localized
        }
    }

    // MARK: - Exercise Verdict

    private struct ExerciseVerdict {
        let label: String
        let fact: String
    }

    /// Classifies an exercise vs. the previous session and resolves one concrete
    /// change fact for it. Only called for exercises with previous data.
    /// The verdict (summed weight/rep deltas) drives the trend icon; the fact
    /// leads with the top set, the number a lifter actually cares about.
    private static func exerciseVerdict(
        _ exercise: WorkoutAnalysisExerciseInput,
        in unit: WeightUnit,
        locale: Locale
    ) -> ExerciseVerdict {
        let unitWord = AICoachUnitVocabulary.unitWord(unit)
        let completedSets = exercise.sets.filter(\.isCompleted)
        let comparable = completedSets.filter { $0.previousWeightKg != nil && $0.previousReps != nil }
        guard !comparable.isEmpty, let curTop = topSet(completedSets) else {
            return ExerciseVerdict(label: "NEW SETS", fact: "no previous sets to compare")
        }

        var totalWeightDelta: Double = 0
        var totalRepsDelta = 0
        for set in comparable {
            totalWeightDelta += set.currentWeightKg - (set.previousWeightKg ?? 0)
            totalRepsDelta += set.currentReps - (set.previousReps ?? 0)
        }

        let prevTop = comparable.max { lhs, rhs in
            (lhs.previousWeightKg ?? 0, lhs.previousReps ?? 0) < (rhs.previousWeightKg ?? 0, rhs.previousReps ?? 0)
        } ?? curTop
        let topWeightDelta = curTop.currentWeightKg - (prevTop.previousWeightKg ?? 0)
        let topNow = "\(fmt(curTop.currentWeightKg, in: unit, locale: locale)) \(unitWord) x \(curTop.currentReps) reps"
        let topPrevious = "\(fmt(prevTop.previousWeightKg ?? 0, in: unit, locale: locale)) \(unitWord) x \(prevTop.previousReps ?? 0) reps"
        let extraSets = completedSets.count - comparable.count

        let weightUp = totalWeightDelta >= 0.01
        let weightDown = totalWeightDelta <= -0.01
        let repsUp = totalRepsDelta > 0
        let repsDown = totalRepsDelta < 0

        let label: String
        var fact: String

        if !weightUp && !weightDown && !repsUp && !repsDown {
            label = "UNCHANGED"
            fact = "same weight and reps as last session (top set \(topNow))"
        } else if (weightUp && repsDown) || (weightDown && repsUp) {
            label = "MIXED"
            fact = "weight \(signed(totalWeightDelta, in: unit, locale: locale)) \(unitWord) but reps \(signedInt(totalRepsDelta)) vs last session (top set \(topNow))"
        } else if weightUp || repsUp {
            label = "IMPROVED"
            if topWeightDelta >= 0.01 {
                fact = "top set +\(fmt(topWeightDelta, in: unit, locale: locale)) \(unitWord): now \(topNow), was \(topPrevious)"
            } else if repsUp {
                fact = "+\(totalRepsDelta) reps in total at the same weight (top set \(topNow))"
            } else {
                fact = "weight +\(fmt(totalWeightDelta, in: unit, locale: locale)) \(unitWord) summed across sets (top set \(topNow))"
            }
        } else {
            label = "DECREASED"
            if topWeightDelta <= -0.01 {
                fact = "top set \(fmt(topWeightDelta, in: unit, locale: locale)) \(unitWord): now \(topNow), was \(topPrevious)"
            } else if repsDown {
                fact = "\(totalRepsDelta) reps in total at the same weight (top set \(topNow))"
            } else {
                fact = "weight \(fmt(totalWeightDelta, in: unit, locale: locale)) \(unitWord) summed across sets (top set \(topNow))"
            }
        }

        if extraSets > 0 {
            fact += ", plus \(extraSets) set(s) more than last time"
        }

        return ExerciseVerdict(label: label, fact: fact)
    }

    // MARK: - Helpers

    /// Heaviest completed set (ties broken by reps).
    private static func topSet(_ sets: [WorkoutAnalysisSetInput]) -> WorkoutAnalysisSetInput? {
        sets.max { ($0.currentWeightKg, $0.currentReps) < ($1.currentWeightKg, $1.currentReps) }
    }

    /// A canonical-kilogram figure as the fact lines write it: the reader's unit, that
    /// unit's precision, and **the reader's decimal separator**.
    ///
    /// The fact lines' *words* are English and the model translates them; their *figures*
    /// are copied verbatim, because the prompt says to copy each one digit for digit
    /// including its separator. So the separator has to be the one the reader should end
    /// up reading. See docs/ai-coach.md § "Prompt grounding rules", rule 1.
    private static func fmt(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        AICoachUnitVocabulary.compact(kilograms, in: unit, locale: locale)
    }

    /// Weight for the reader's own sentence: the locale's decimal separator, no
    /// trailing ",0", and the unit word attached — "16 kg", "181,9 lb", matching how
    /// weights read everywhere else in the app.
    private static func weightLabel(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        let rounded = (unit.roundedDisplay(fromKilograms: kilograms) * 10).rounded() / 10
        let format = rounded == rounded.rounded() ? "%.0f" : "%.1f"
        let number = String(format: format, locale: locale, rounded)
        return "\(number) \(AICoachUnitVocabulary.unitWord(unit))"
    }

    private static func signed(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        kilograms >= 0 ? "+\(fmt(kilograms, in: unit, locale: locale))" : fmt(kilograms, in: unit, locale: locale)
    }

    private static func signedInt(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}
