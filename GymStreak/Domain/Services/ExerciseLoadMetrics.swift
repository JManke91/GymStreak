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
}
