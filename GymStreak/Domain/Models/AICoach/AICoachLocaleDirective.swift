//
//  AICoachLocaleDirective.swift
//  GymStreak
//

import Foundation

/// The two sentences Apple documents for steering the on-device model's **output
/// language**, prepended to an otherwise-English system prompt.
///
/// **Instructions stay in English; only the directive names the output language.** That is
/// counter-intuitive and it is Apple's documented guidance, not a preference of ours:
/// *Supporting languages and locales with Foundation Models* says to "start with the exact
/// phrase in English, which comes from the model's training, and reduces the possibility of
/// hallucinations in multilingual situations", and gives `"You MUST respond in <language>."`
/// as the pattern. Writing the instructions themselves in German was tried here first and
/// reverted: Apple documents no such approach, and English instructions with an explicit
/// directive is the supported path rather than a workaround.
///
/// The rule it replaces — "Write in the language indicated by the `locale` field. For 'de_*'
/// use German" — asked the model to parse a condition and apply it, instead of stating the
/// answer. The German that came back read like literal translation: "die die gesamte
/// Zeitraum", "des Bizeps-Curls-Übens", "unterschiedlichen Trainingsschritten und
/// Zielgruppen" (*target audiences*, for rep-range goals).
///
/// - SeeAlso: https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models
enum AICoachLocaleDirective {

    /// The directive block for `localeIdentifier`, or an empty string for US English —
    /// which is the model's own default and needs no steering, exactly as Apple's sample
    /// `localeInstructions(for:)` returns `""` for it.
    ///
    /// The language is named **in English** ("German", not "Deutsch") for the same reason
    /// the surrounding instructions are: the phrase has to be the one the model was trained
    /// on.
    static func lines(forLocaleIdentifier localeIdentifier: String) -> String {
        let locale = Locale(identifier: localeIdentifier)
        guard !Locale.Language(identifier: "en_US").isEquivalent(to: locale.language) else {
            return ""
        }
        guard let code = locale.language.languageCode?.identifier,
              let englishName = Locale(identifier: "en_US").localizedString(forLanguageCode: code)
        else {
            return ""
        }
        return """
        The person's locale is \(localeIdentifier).
        You MUST respond in \(englishName).

        """
    }
}
