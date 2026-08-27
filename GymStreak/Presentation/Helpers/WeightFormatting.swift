import Foundation

/// The app's single weight-formatting seam: converts the canonical kilograms
/// into the user's unit and renders it locale-aware and trailing-zero-free
/// ("90", "37,5", "198,4 lb").
///
/// It replaced three parallel implementations (a `FloatingPointFormatStyle`
/// helper, `WorkoutValueFormatting.weight`'s hand-rolled separator swap, and
/// `SetSummaryFormatting`'s own call into the first) — that drift is exactly how
/// "kg" ended up baked into twenty localized values. Everything that renders a
/// weight goes through here.
///
/// The format styles are `static let` because these strings are produced once
/// per set row per render (see CLAUDE.md, rendering rules), and because
/// `MeasurementFormatter` — the obvious alternative — is a mutable `NSObject`
/// that is not `Sendable` and so cannot be hoisted at all in this Swift 6 build.
/// The unit word comes from `Localizable.strings` rather than
/// `.formatted(.measurement(...))`, whose default `usage: .general` re-derives
/// the unit from the locale and would contradict the value just converted.
enum WeightFormatting {

    // MARK: - Format styles

    private static let kilogramStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)

    /// One digit is enough for pounds: their grid is 0.5 lb, and a converted
    /// figure carries no meaningful second decimal.
    private static let poundStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...1))
        .grouping(.never)

    private static func style(for unit: WeightUnit) -> FloatingPointFormatStyle<Double> {
        switch unit {
        case .kilograms: kilogramStyle
        case .pounds: poundStyle
        }
    }

    /// The style a `TextField(value:format:)` edits a weight in — the same one
    /// the read-only sites use, exposed so a field never builds its own.
    static func inputStyle(for unit: WeightUnit) -> FloatingPointFormatStyle<Double> {
        style(for: unit)
    }

    // MARK: - Unit words

    /// The written unit: "kg" / "lb".
    static func unitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: "unit.weight.kg".localized
        case .pounds: "unit.weight.lb".localized
        }
    }

    /// The spoken unit, for VoiceOver: "kilograms" / "pounds". A screen reader
    /// saying "kay gee" is the reason this exists.
    static func spokenUnitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: "unit.weight.kg.spoken".localized
        case .pounds: "unit.weight.lb.spoken".localized
        }
    }

    /// The unit's own name for a standalone label such as the Settings picker:
    /// "Kilograms" / "Pounds". Capitalized from the spoken word so the unit
    /// still lives in one pair of keys instead of three.
    static func unitName(_ unit: WeightUnit) -> String {
        spokenUnitWord(unit).localizedCapitalized
    }

    // MARK: - Canonical kilograms in

    /// Bare number, converted from the canonical kilograms: "90", "198,4".
    static func number(_ kilograms: Double, in unit: WeightUnit) -> String {
        displayNumber(unit.converting(fromKilograms: kilograms), in: unit)
    }

    /// Number with the unit word: "90 kg", "198,4 lb".
    static func label(_ kilograms: Double, in unit: WeightUnit) -> String {
        "set.weight_compact".localized(number(kilograms, in: unit), unitWord(unit))
    }

    /// Number with the spoken unit word, for accessibility labels.
    static func spokenLabel(_ kilograms: Double, in unit: WeightUnit) -> String {
        "set.weight_compact".localized(number(kilograms, in: unit), spokenUnitWord(unit))
    }

    // MARK: - Display space in

    /// Bare number for a value that is *already* in `unit` — a stepper delta, a
    /// figure the user just typed. Never hand this canonical kilograms: it does
    /// not convert, by design.
    static func displayNumber(_ display: Double, in unit: WeightUnit) -> String {
        display.formatted(style(for: unit))
    }
}
