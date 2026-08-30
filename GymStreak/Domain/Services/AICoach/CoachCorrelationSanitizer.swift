//
//  CoachCorrelationSanitizer.swift
//  GymStreak
//
//  Decides whether the period recap's optional correlation field holds a real finding.
//  See docs/ai-coach.md § "Prompt grounding rules (binding, all surfaces)", rules 3 and 4.
//

import Foundation

/// The `PeriodRecapOutput.correlationHighlight` the Auffälligkeiten card should actually
/// show, or `nil` when the model filled a field it was told to leave out.
///
/// **Two ways it fills it, and both are rejected here.**
///
/// A *placeholder*: asked to "return nil for this field", the model wrote the
/// four-character string `nil`, and the card rendered it verbatim under the `MUSTER`
/// label (German, on device, 2026-08-30). The prompt and the `@Guide` no longer name a
/// programming construct, but the field is the model's to fill, so the placeholder is
/// caught here too — the half of the guarantee that does not depend on the model obeying
/// anything.
///
/// An *apology*: "There are no notable correlations…". The prompt's pattern statements
/// are pre-written findings the model reproduces almost verbatim, so only explicit
/// "nothing found" phrasing needs catching — a subject-matching heuristic (short text
/// without a known exercise name → apologetic) was tried and removed, because the real
/// statements are short and contain no exercise names either.
///
/// Applied at three sites, all in `PeriodRecapViewModel` / `AICoachCache`: the streamed
/// partial (which is what the card renders while generating, and where `nil` arrives
/// first), the final output, and the cache read — a recap cached before this guard
/// existed can still hold a literal `nil`, and a cache entry is never regenerated just
/// because its prose is stale.
///
/// **Isolation-agnostic on purpose.** It is pure `String? -> String?` over model output
/// with no state, so it stays out of `Presentation/` and needs no actor.
enum CoachCorrelationSanitizer {

    /// A whole answer that is nothing but a placeholder token. Matched against the
    /// **entire** trimmed string, never as a substring, so a real sentence containing
    /// "none" or "keine" survives to the apology check on its own merits.
    private static let placeholders: Set<String> = [
        "nil", "null", "none", "nothing", "empty", "n/a", "na",
        "keine", "keins", "kein", "nichts", "leer", "unbekannt"
    ]

    private static let apologies: [String] = [
        "no correlation", "no notable", "no pattern", "not enough data",
        "keine korrelation", "keine zusammenhänge", "keine muster",
        "keine auffälligkeiten", "nicht genug daten"
    ]

    /// Punctuation and quoting a bare placeholder may arrive wrapped in — `"nil."`,
    /// `(none)`, `— `.
    private static let placeholderTrimSet = CharacterSet(charactersIn: ".!:;\"'()[]-–—_ ")

    static func sanitized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let bare = trimmed.lowercased().trimmingCharacters(in: placeholderTrimSet)
        if bare.isEmpty || placeholders.contains(bare) { return nil }

        let lower = trimmed.lowercased()
        return apologies.contains { lower.contains($0) } ? nil : trimmed
    }
}
