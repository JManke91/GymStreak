//
//  PostWorkoutRecapInput.swift
//  GymStreak
//

import Foundation
import FoundationModels

@Generable
struct PostWorkoutRecapInput {
    @Guide(description: "User's locale identifier, e.g. 'de_DE' or 'en_US'")
    let locale: String

    @Guide(description: "Total volume of this workout in kilograms")
    let workoutVolumeKg: Double

    @Guide(description: "Total number of working sets")
    let totalSets: Int

    @Guide(description: "Workout duration in minutes")
    let durationMinutes: Int

    @Guide(description: "Primary muscle groups trained, in order of volume")
    let muscleGroupsTrained: [MuscleGroupSummary]

    @Guide(description: "New personal records achieved in this session")
    let newPRs: [PRSummary]

    @Guide(description: "Sessions completed in the last 7 days including this one")
    let sessionsThisWeek: Int
}

@Generable
struct MuscleGroupSummary {
    @Guide(description: "Name of the muscle group, e.g. 'Chest' or 'Quadriceps'")
    let name: String

    @Guide(description: "Total volume lifted for this muscle group in kilograms")
    let volumeKg: Double

    @Guide(description: "Percentage change vs four-week average, e.g. +12 or -8")
    let percentVsFourWeekAverage: Int
}

@Generable
struct PRSummary {
    @Guide(description: "Name of the exercise where the PR was set")
    let exerciseName: String

    @Guide(description: "Weight lifted in kilograms for the PR set")
    let weightKg: Double

    @Guide(description: "Number of reps performed in the PR set")
    let reps: Int
}

// MARK: - Prompt Serialisation

extension PostWorkoutRecapInput {
    /// Produces a plain-text serialisation suitable for use as the user-turn prompt
    /// in a `LanguageModelSession`. Keeps all values factual and readable.
    ///
    /// **This is the conversion boundary.** The stored properties above stay
    /// canonical kilograms — which is what keeps their `…Kg` names and their
    /// `@Guide` descriptions true — and every figure is converted here, once, on
    /// its way into the string the model reads. See docs/weight-unit-preference.md §13.
    ///
    /// - Parameter unit: the unit the reader has chosen. `PostWorkoutRecapInstructions`
    ///   must be built with the same one, or the prompt tells the model to echo a unit
    ///   the figures are not in.
    func toPromptText(in unit: WeightUnit) -> String {
        let unitWord = AICoachUnitVocabulary.unitWord(unit)
        func weight(_ kilograms: Double) -> String {
            "\(AICoachUnitVocabulary.decimal(kilograms, in: unit, locale: Locale(identifier: locale))) \(unitWord)"
        }
        var lines: [String] = []
        lines.append("Locale: \(locale)")
        lines.append("Workout volume: \(weight(workoutVolumeKg))")
        lines.append("Total sets: \(totalSets)")
        lines.append("Duration: \(durationMinutes) min")
        lines.append("Sessions this week (including today): \(sessionsThisWeek)")
        lines.append("Muscle groups trained, in order of volume:")
        for g in muscleGroupsTrained {
            let delta = g.percentVsFourWeekAverage >= 0
                ? "+\(g.percentVsFourWeekAverage)%"
                : "\(g.percentVsFourWeekAverage)%"
            lines.append("  - \(g.name): \(weight(g.volumeKg)) (\(delta) vs 4-week average)")
        }
        if newPRs.isEmpty {
            lines.append("New PRs: none")
        } else {
            lines.append("New PRs:")
            for pr in newPRs {
                lines.append("  - \(pr.exerciseName): \(weight(pr.weightKg)) × \(pr.reps)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
