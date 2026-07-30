import Foundation

/// Locale-aware, trailing-zero-free weight formatting for set rows and summaries
/// ("90", "37,5"). The format style is hoisted to a `static let` — these strings
/// are produced once per set row per render (see CLAUDE.md, rendering rules).
enum WeightFormatting {
    private static let style = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)

    /// Bare number, no unit: "90", "37,5".
    static func number(_ weight: Double) -> String {
        weight.formatted(style)
    }

    /// Number with the kg unit: "90 kg".
    static func label(_ weight: Double) -> String {
        "set.weight_compact".localized(number(weight))
    }
}
