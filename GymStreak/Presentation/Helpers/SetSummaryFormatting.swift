import Foundation

/// Compact one-line description of a set scheme, used in exercise card headers,
/// sorting rows and alternative rows: "3 × 6 Wdh · 90 kg" when every set shares
/// the same reps and weight, otherwise "3 Sätze · max 90 kg".
enum SetSummaryFormatting {

    /// The unit these summaries render in. Routine cards are ticket 02's
    /// surface: until they read the user's unit from the environment, the
    /// summary stays in the canonical kilograms rather than showing a converted
    /// figure next to the kilogram values their set editors still display.
    private static let unit = WeightUnit.kilograms

    static func text(reps: [Int], weights: [Double]) -> String {
        guard !reps.isEmpty else { return "routine.sets_count".localized(0) }

        if let uniform = RoutineMetricsService.uniformSetScheme(reps: reps, weights: weights), uniform.weight > 0 {
            return "routine.set_scheme.uniform".localized(
                reps.count,
                uniform.reps,
                WeightFormatting.label(uniform.weight, in: unit)
            )
        }

        guard let heaviest = weights.max(), heaviest > 0 else {
            return "routine.sets_count".localized(reps.count)
        }
        return "routine.set_scheme.mixed".localized(reps.count, WeightFormatting.label(heaviest, in: unit))
    }
}
