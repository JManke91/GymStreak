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

    @Guide(description: "Date of the current workout in ISO 8601 format")
    let currentWorkoutDate: String

    @Guide(description: "Duration of the current workout in minutes")
    let currentDurationMinutes: Int

    @Guide(description: "Total volume of the current workout in kilograms")
    let currentTotalVolumeKg: Double

    @Guide(description: "Total number of completed sets in the current workout")
    let currentTotalSets: Int

    @Guide(description: "Completion percentage of the current workout (0-100)")
    let currentCompletionPercentage: Int

    @Guide(description: "Date of the previous session of the same routine in ISO 8601 format")
    let previousWorkoutDate: String

    @Guide(description: "Total volume of the previous session in kilograms")
    let previousTotalVolumeKg: Double

    @Guide(description: "Total number of completed sets in the previous session")
    let previousTotalSets: Int

    @Guide(description: "Per-exercise comparison data for each exercise in this workout")
    let exercises: [WorkoutAnalysisExerciseInput]

    @Guide(description: "New personal records achieved in this session")
    let newPRs: [PRSummary]
}

@Generable
struct WorkoutAnalysisExerciseInput {
    @Guide(description: "Name of the exercise")
    let exerciseName: String

    @Guide(description: "Total volume for this exercise in kilograms in the current session")
    let currentVolumeKg: Double

    @Guide(description: "Number of completed sets for this exercise in the current session")
    let currentSetsCount: Int

    @Guide(description: "Total reps completed for this exercise in the current session")
    let currentTotalReps: Int

    @Guide(description: "Whether this is the first time performing this exercise (no previous data)")
    let isFirstTime: Bool

    @Guide(description: "Volume change vs. previous in kilograms, nil if first time")
    let volumeDeltaKg: Double?

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
    /// Produces a plain-text serialisation suitable for use as the user-turn prompt
    /// in a `LanguageModelSession`. Pre-computes per-exercise verdicts
    /// (IMPROVED / UNCHANGED / DECREASED) so the on-device model only
    /// narrates — it does not need to reason about the numbers.
    func toPromptText() -> String {
        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Routine: \(routineName)")
        lines.append("Current session: \(currentWorkoutDate), \(currentTotalSets) sets, \(currentDurationMinutes) min")
        lines.append("Previous session: \(previousWorkoutDate), \(previousTotalSets) sets")
        lines.append("")

        for exercise in exercises {
            if exercise.isFirstTime {
                lines.append("\(exercise.exerciseName) [NEW EXERCISE]:")
                let completedSets = exercise.sets.filter(\.isCompleted)
                for set in completedSets {
                    let w = String(format: "%g", set.currentWeightKg)
                    lines.append("  Set \(set.setNumber): \(w) kg x \(set.currentReps) reps")
                }
                continue
            }

            // Pre-compute the exercise-level verdict
            let verdict = Self.exerciseVerdict(exercise)
            lines.append("\(exercise.exerciseName) [\(verdict.label)]:")
            if !verdict.detail.isEmpty {
                lines.append("  Summary: \(verdict.detail)")
            }

            let completedSets = exercise.sets.filter(\.isCompleted)
            for set in completedSets {
                let w = String(format: "%g", set.currentWeightKg)
                var setLine = "  Set \(set.setNumber): \(w) kg x \(set.currentReps) reps"

                if let pw = set.previousWeightKg, let pr = set.previousReps {
                    let prevW = String(format: "%g", pw)
                    let wDiff = set.currentWeightKg - pw
                    let rDiff = set.currentReps - pr

                    if abs(wDiff) < 0.01 && rDiff == 0 {
                        setLine += " → unchanged"
                    } else {
                        var changes: [String] = []
                        if abs(wDiff) >= 0.01 {
                            let sign = wDiff > 0 ? "+" : ""
                            changes.append("\(sign)\(String(format: "%g", wDiff)) kg")
                        }
                        if rDiff != 0 {
                            let sign = rDiff > 0 ? "+" : ""
                            changes.append("\(sign)\(rDiff) reps")
                        }
                        setLine += " → \(changes.joined(separator: ", ")) (was \(prevW) kg x \(pr))"
                    }
                }
                lines.append(setLine)
            }
        }

        if !newPRs.isEmpty {
            lines.append("")
            lines.append("New PRs:")
            for pr in newPRs {
                lines.append("- \(pr.exerciseName): \(String(format: "%.1f", pr.weightKg)) kg x \(pr.reps)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Exercise Verdict

    private struct ExerciseVerdict {
        let label: String
        let detail: String
    }

    /// Pre-computes whether an exercise improved, stayed the same, or regressed
    /// based on weight and rep changes across its completed sets.
    private static func exerciseVerdict(_ exercise: WorkoutAnalysisExerciseInput) -> ExerciseVerdict {
        let completedSets = exercise.sets.filter(\.isCompleted)
        var totalWeightDelta: Double = 0
        var totalRepsDelta: Int = 0
        var comparableSets = 0

        for set in completedSets {
            guard let pw = set.previousWeightKg, let pr = set.previousReps else { continue }
            comparableSets += 1
            totalWeightDelta += set.currentWeightKg - pw
            totalRepsDelta += set.currentReps - pr
        }

        guard comparableSets > 0 else {
            return ExerciseVerdict(label: "NEW SETS", detail: "Added new sets with no previous data")
        }

        let hasWeightChange = abs(totalWeightDelta) >= 0.01
        let hasRepsChange = totalRepsDelta != 0

        if !hasWeightChange && !hasRepsChange {
            return ExerciseVerdict(label: "UNCHANGED", detail: "Same weight and reps as previous session")
        }

        var details: [String] = []

        if hasWeightChange {
            let sign = totalWeightDelta > 0 ? "+" : ""
            details.append("\(sign)\(String(format: "%g", totalWeightDelta)) kg total weight change")
        }

        if hasRepsChange {
            let sign = totalRepsDelta > 0 ? "+" : ""
            details.append("\(sign)\(totalRepsDelta) total reps change")
        }

        if totalWeightDelta > 0 || (abs(totalWeightDelta) < 0.01 && totalRepsDelta > 0) {
            return ExerciseVerdict(label: "IMPROVED", detail: details.joined(separator: ", "))
        } else if totalWeightDelta < 0 || (abs(totalWeightDelta) < 0.01 && totalRepsDelta < 0) {
            return ExerciseVerdict(label: "DECREASED", detail: details.joined(separator: ", "))
        } else {
            // Mixed: weight up but reps down, or vice versa
            return ExerciseVerdict(label: "MIXED", detail: details.joined(separator: ", "))
        }
    }
}
