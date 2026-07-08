//
//  WorkoutAnalysisInput.swift
//  GymStreak
//
//  Input struct for the workout detail AI Coach analysis surface.
//  Compares a completed workout session against the previous session
//  of the same routine.
//

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

    @Guide(description: "Previous weight for this set number in kilograms, nil if no previous data")
    let previousWeightKg: Double?

    @Guide(description: "Previous reps for this set number, nil if no previous data")
    let previousReps: Int?
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
    func toPromptText() -> String {
        // First-time exercises have no baseline: they never become highlights,
        // only a closing-observation note.
        let comparableExercises = exercises.filter { !$0.isFirstTime }
        let firstTimeNames = exercises.filter(\.isFirstTime).map(\.exerciseName)
        let verdicts = comparableExercises.map(Self.exerciseVerdict)

        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Routine: \(routineName)")
        lines.append("Current session: \(currentTotalSets) sets, \(currentDurationMinutes) min")
        lines.append("Previous session (\(daysSincePrevious) days earlier): \(previousTotalSets) sets")
        lines.append("Headline fact: \(headlineFact(verdicts: verdicts))")

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
                lines.append("- \(pr.exerciseName): \(Self.fmt(pr.weightKg)) kg x \(pr.reps) reps")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Headline Fact

    /// Resolves the single most important story of the session, in priority order:
    /// new PR > all/majority improved > all/majority declined > unchanged > mixed.
    private func headlineFact(verdicts: [ExerciseVerdict]) -> String {
        if let pr = newPRs.first {
            var fact = "new personal record on \(pr.exerciseName): \(Self.fmt(pr.weightKg)) kg x \(pr.reps) reps"
            if newPRs.count > 1 {
                fact += " (and \(newPRs.count - 1) more PRs)"
            }
            return fact
        }

        let comparableLabels: Set<String> = ["IMPROVED", "DECREASED", "MIXED", "UNCHANGED"]
        let comparable = verdicts.filter { comparableLabels.contains($0.label) }
        let improved = comparable.filter { $0.label == "IMPROVED" }.count
        let declined = comparable.filter { $0.label == "DECREASED" }.count
        let mixed = comparable.filter { $0.label == "MIXED" }.count
        let total = comparable.count

        guard total > 0 else {
            return "first comparable session — no previous exercise data"
        }
        if improved > 0 && declined == 0 && mixed == 0 {
            return improved == total
                ? "all \(total) exercises improved vs last session"
                : "\(improved) of \(total) exercises improved, the rest unchanged"
        }
        if declined > 0 && improved == 0 && mixed == 0 {
            return declined == total
                ? "all \(total) exercises below last session"
                : "\(declined) of \(total) exercises below last session, the rest unchanged"
        }
        if improved == 0 && declined == 0 && mixed == 0 {
            return "same weights and reps as last session across all \(total) exercises"
        }
        var fact = "mixed session: \(improved) improved, \(declined) declined"
        if mixed > 0 {
            fact += ", \(mixed) up and down"
        }
        return fact
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
    private static func exerciseVerdict(_ exercise: WorkoutAnalysisExerciseInput) -> ExerciseVerdict {
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
        let topNow = "\(fmt(curTop.currentWeightKg)) kg x \(curTop.currentReps) reps"
        let topPrevious = "\(fmt(prevTop.previousWeightKg ?? 0)) kg x \(prevTop.previousReps ?? 0) reps"
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
            fact = "weight \(signed(totalWeightDelta)) kg but reps \(signedInt(totalRepsDelta)) vs last session (top set \(topNow))"
        } else if weightUp || repsUp {
            label = "IMPROVED"
            if topWeightDelta >= 0.01 {
                fact = "top set +\(fmt(topWeightDelta)) kg: now \(topNow), was \(topPrevious)"
            } else if repsUp {
                fact = "+\(totalRepsDelta) reps in total at the same weight (top set \(topNow))"
            } else {
                fact = "weight +\(fmt(totalWeightDelta)) kg summed across sets (top set \(topNow))"
            }
        } else {
            label = "DECREASED"
            if topWeightDelta <= -0.01 {
                fact = "top set \(fmt(topWeightDelta)) kg: now \(topNow), was \(topPrevious)"
            } else if repsDown {
                fact = "\(totalRepsDelta) reps in total at the same weight (top set \(topNow))"
            } else {
                fact = "weight \(fmt(totalWeightDelta)) kg summed across sets (top set \(topNow))"
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

    private static func fmt(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private static func signed(_ value: Double) -> String {
        value >= 0 ? "+\(fmt(value))" : fmt(value)
    }

    private static func signedInt(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}
