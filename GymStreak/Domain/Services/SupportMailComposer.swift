//
//  SupportMailComposer.swift
//  GymStreak
//
//  Builds the `mailto:` URL behind the Settings → Support → "Contact support"
//  row. See docs/settings-tab.md.
//

import Foundation

/// Composes the support mail's `mailto:` URL.
///
/// Localization-agnostic on purpose: the caller passes the already-localized
/// subject and intro line, so this stays pure and unit-testable.
enum SupportMailComposer {

    /// Builds `mailto:<recipient>?subject=…&body=…`.
    ///
    /// Assembled with `URLComponents`/`URLQueryItem` rather than string
    /// interpolation: RFC 6068 requires the `subject` and `body` values to be
    /// percent-encoded, and the diagnostic block contains newlines that a
    /// hand-built string would corrupt or truncate. The `queryItems` setter
    /// escapes newlines, `&`, `=` and `#` inside the values (verified by
    /// `SupportMailComposerTests`), so no manual encoding pass is needed.
    ///
    /// - Returns: `nil` only if the recipient cannot form a valid URL.
    static func mailtoURL(
        recipient: String,
        subject: String,
        intro: String,
        diagnostics: DeviceDiagnostics
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(intro: intro, diagnostics: diagnostics))
        ]
        return components.url
    }

    /// Two blank lines for the user to write in, then the intro and the block.
    private static func body(intro: String, diagnostics: DeviceDiagnostics) -> String {
        let block = [
            "App: \(diagnostics.appVersion) (\(diagnostics.buildNumber))",
            "iOS: \(diagnostics.systemVersion)",
            "Device: \(diagnostics.deviceModel)",
            "Locale: \(diagnostics.localeIdentifier)"
        ].joined(separator: "\n")
        return "\n\n\(intro)\n\(block)"
    }
}
