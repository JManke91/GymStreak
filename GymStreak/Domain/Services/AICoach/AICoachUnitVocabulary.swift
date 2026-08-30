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
    /// written without a trailing `.0` — "87.5", "220.5", "40".
    ///
    /// The C locale is deliberate: this rendering feeds the fact lines that are
    /// uniformly English (`ChatFactBuilder`, `WorkoutAnalysisInput`). Where a
    /// surface writes its figures in the reader's own convention instead — the
    /// deep dive does, so the model only ever copies them — use
    /// `decimal(_:in:locale:)`.
    ///
    /// Trailing zeros are trimmed by hand rather than with `%g`, whose six
    /// significant digits turn a real all-time tonnage into `1.23457e+06`.
    static func compact(_ kilograms: Double, in unit: WeightUnit) -> String {
        var text = String(format: "%.\(unit.fractionDigits)f", unit.roundedDisplay(fromKilograms: kilograms))
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// A weight for a prompt line or a reader-facing sentence, in the reader's own
    /// decimal convention and always with one decimal place — "20,0" / "20.0".
    static func decimal(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        String(format: "%.1f", locale: locale, unit.converting(fromKilograms: kilograms))
    }

    // MARK: - Phrases

    /// A finished "44.1 lb" for a compound format string that takes the weight via
    /// `%@` — the pattern `docs/weight-unit-preference.md` §7 makes binding for
    /// every localized weight in the app.
    static func labelled(_ kilograms: Double, in unit: WeightUnit, locale: Locale) -> String {
        "\(decimal(kilograms, in: unit, locale: locale)) \(unitWord(unit))"
    }
}
