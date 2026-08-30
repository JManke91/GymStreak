//
//  AICoachUnitVocabulary.swift
//  GymStreak
//
//  The words and numbers the AI Coach writes a weight with. See
//  docs/weight-unit-preference.md §13 and docs/ai-coach.md §7.
//

import Foundation

/// Renders a canonical-kilogram weight the way the coach layer needs it: as a
/// prompt figure the model is told to copy, and as a finished phrase for the two
/// sentences Swift composes itself (`ExerciseDeepDiveInput.peakSentence`,
/// `WorkoutAnalysisInput.headlineSentence`).
///
/// **Why this is not `WeightFormatting`.** That seam lives in `Presentation/`, and
/// `Domain/` may not depend on it (architecture Hard rule: `Presentation → Domain`).
/// The shared source of truth is not the function but the strings table: the unit
/// word below is read from the very same `unit.weight.*` keys, so a coach sentence
/// and the chart headline above it cannot disagree about what a pound is called.
///
/// Everything here takes **canonical kilograms** and converts, exactly once, at the
/// moment the string is made. Nothing in the coach layer ever converts twice,
/// because no converted value is ever stored back into an input DTO — the DTOs stay
/// kilograms and their `…Kg` names stay accurate.
enum AICoachUnitVocabulary {

    // MARK: - Words

    /// The written unit — "kg" / "lb". Identical in every language the app ships,
    /// which is why an English prompt and a German sentence can share it.
    static func unitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: "unit.weight.kg".localized
        case .pounds: "unit.weight.lb".localized
        }
    }

    /// The unit's English name — "kilograms" / "pounds". For the instruction
    /// sentences, which stay English whatever the reply language is
    /// (`AICoachLocaleDirective`).
    static func englishName(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: "kilograms"
        case .pounds: "pounds"
        }
    }

    // MARK: - Numbers

    /// A weight for a prompt line: converted, rounded to the unit's precision, and
    /// written without a trailing `.0` — "87,5", "220,5", "40".
    ///
    /// **The locale is the reader's, not the C locale.** Every narrating coach prompt
    /// now tells the model to copy each figure "digit for digit, including its decimal
    /// separator" (docs/ai-coach.md § "Prompt grounding rules", rule 1), and it obeys:
    /// a figure rendered as `1830.0` came back inside a German sentence as `1830.0 kg`
    /// (device, 2026-08-30). A model that is told to copy verbatim must be handed the
    /// string the reader should see, which is what `ExerciseDeepDiveInput` has always
    /// done. Pass `en_US_POSIX` only for a figure that is genuinely not a reader-facing
    /// number.
    ///
    /// Trailing zeros are trimmed by hand rather than with `%g`, whose six
    /// significant digits turn a real all-time tonnage into `1.23457e+06`.
    static func compact(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        var text = fixed(unit.roundedDisplay(fromKilograms: kilograms), places: unit.fractionDigits, locale: locale)
        let separator = locale.decimalSeparator ?? "."
        guard text.hasSuffix("0"), text.contains(separator) else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(separator) { text.removeLast() }
        return text
    }

    /// A weight for a prompt line or a reader-facing sentence, in the reader's own
    /// decimal convention and always with one decimal place — "20,0" / "20.0".
    ///
    /// Same rule as `compact(_:in:locale:)`: a prompt figure carries the reader's
    /// separator, because the prompt tells the model to copy it verbatim.
    static func decimal(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        fixed(unit.converting(fromKilograms: kilograms), places: 1, locale: locale)
    }

    /// A figure that is not a weight — a frequency, a percentage — at one decimal, in the
    /// reader's convention. Same rule as the weights: a prompt figure carries the reader's
    /// separator because the model is told to copy it verbatim.
    static func plainDecimal(_ value: Double, locale: Locale) -> String {
        fixed(value, places: 1, locale: locale)
    }

    /// `value` at `places` decimals, carrying the locale's decimal separator and **no
    /// grouping separator**.
    ///
    /// `String(format:locale:)` cannot be used directly: handed a locale it also inserts
    /// grouping separators, so an all-time tonnage came out as `1,234,567.8` where the
    /// caller needs `1234567.8`. Worse for a prompt figure, German groups with the period
    /// and separates decimals with the comma, so `1.830,0` puts two locale-dependent
    /// characters into a string the model is told to copy character for character.
    ///
    /// Formatting in the C locale and substituting only the separator keeps the change to
    /// exactly the one character that was wrong.
    private static func fixed(_ value: Double, places: Int, locale: Locale) -> String {
        let text = String(format: "%.\(places)f", value)
        guard let separator = locale.decimalSeparator, separator != "." else { return text }
        return text.replacingOccurrences(of: ".", with: separator)
    }

    // MARK: - Phrases

    /// A finished "44.1 lb" for a compound format string that takes the weight via
    /// `%@` — the pattern `docs/weight-unit-preference.md` §7 makes binding for
    /// every localized weight in the app.
    static func labelled(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        "\(decimal(kilograms, in: unit, locale: locale)) \(unitWord(unit))"
    }
}
