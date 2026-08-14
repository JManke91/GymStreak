import Foundation

/// Direction-aware calculations for resistance and counterweight exercises.
/// Counterweight assistance is only converted into physical load when the
/// workout has a body-mass snapshot; without one, callers can still compare
/// the raw assistance direction but must not manufacture volume or 1RM data.
enum ExerciseLoadMetrics {
    static func effectiveWeight(
        enteredWeight: Double,
        behavior: ExerciseLoadBehavior,
        bodyWeightKg: Double?
    ) -> Double? {
        switch behavior {
        case .resistance:
            return enteredWeight
        case .counterweightAssistance:
            guard let bodyWeightKg else { return nil }
            return max(0, bodyWeightKg - enteredWeight)
        }
    }

    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30.0)
    }

    /// True when an entered-weight decrease represents a performance gain.
    static func isImprovement(current: Double, previous: Double, behavior: ExerciseLoadBehavior) -> Bool {
        switch behavior {
        case .resistance: current > previous
        case .counterweightAssistance: current < previous
        }
    }

    static func signedEnteredWeightDelta(current: Double, previous: Double, behavior: ExerciseLoadBehavior) -> Double {
        let delta = current - previous
        return behavior.isCounterweightAssistance ? -delta : delta
    }

    /// Total effective load moved by `sets`: Σ (effective weight × reps).
    ///
    /// `nil` for counterweight-assistance work with no body-mass snapshot — there is no
    /// physical load to sum, and manufacturing one would make a comparison lie.
    ///
    /// The one place this lives, because both halves of the exercise comparison need it
    /// and they run on different executors: the current workout's volume is computed on
    /// the main actor by `ExerciseComparisonBuilder`, the previous workout's inside the
    /// model actor by `PreviousPerformanceResolver` (audit P1.6).
    static func effectiveVolume(
        from sets: [WorkoutSet],
        usePlannedValues: Bool,
        behavior: ExerciseLoadBehavior,
        bodyWeightKg: Double?
    ) -> Double? {
        if behavior.isCounterweightAssistance && bodyWeightKg == nil {
            return nil
        }
        return sets.reduce(0) { total, set in
            let enteredWeight = usePlannedValues ? set.plannedWeight : set.actualWeight
            let reps = usePlannedValues ? set.plannedReps : set.actualReps
            let weight = effectiveWeight(
                enteredWeight: enteredWeight,
                behavior: behavior,
                bodyWeightKg: bodyWeightKg
            ) ?? 0
            return total + weight * Double(reps)
        }
    }
}
