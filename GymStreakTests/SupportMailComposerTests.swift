//
//  SupportMailComposerTests.swift
//  GymStreakTests
//
//  The Settings support mail's `mailto:` URL. The percent-encoding is the whole
//  point of the type — the body carries newlines, and a subject or intro line
//  may contain `&`, both of which silently truncate a hand-built URL.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct SupportMailComposerTests {

    private static let fixture = DeviceDiagnostics(
        appVersion: "1.4.0",
        buildNumber: "128",
        systemVersion: "26.5",
        deviceModel: "iPhone17,1",
        localeIdentifier: "de_DE"
    )

    /// Decodes the built URL back into its parts, which is exactly what a mail
    /// client does — so a broken encoding shows up as a wrong value here.
    private func makeParts(
        subject: String = "Gym Streak support request",
        intro: String = "Sent along to help with troubleshooting:"
    ) throws -> (recipient: String, subject: String, body: String) {
        let url = try #require(
            SupportMailComposer.mailtoURL(
                recipient: "julian.manke@googlemail.com",
                subject: subject,
                intro: intro,
                diagnostics: Self.fixture
            )
        )
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        let decodedSubject = try #require(items.first { $0.name == "subject" }?.value)
        let decodedBody = try #require(items.first { $0.name == "body" }?.value)
        return (recipient: components.path, subject: decodedSubject, body: decodedBody)
    }

    @Test("Addresses the support mailbox with the given subject")
    func recipientAndSubject() throws {
        let parts = try makeParts()
        #expect(parts.recipient == "julian.manke@googlemail.com")
        #expect(parts.subject == "Gym Streak support request")
    }

    @Test("Body carries every diagnostic field, one per line, below the intro")
    func bodyContainsDiagnostics() throws {
        let parts = try makeParts()
        let lines = parts.body.components(separatedBy: "\n")
        // Two blank lines first, so the user's cursor starts above the block.
        #expect(Array(lines.prefix(2)) == ["", ""])
        #expect(Array(lines.dropFirst(2)) == [
            "Sent along to help with troubleshooting:",
            "App: 1.4.0 (128)",
            "iOS: 26.5",
            "Device: iPhone17,1",
            "Locale: de_DE"
        ])
    }

    @Test("Newlines are percent-encoded in the raw URL but survive decoding")
    func newlinesArePercentEncoded() throws {
        let url = try #require(
            SupportMailComposer.mailtoURL(
                recipient: "julian.manke@googlemail.com",
                subject: "Subject",
                intro: "Intro",
                diagnostics: Self.fixture
            )
        )
        #expect(!url.absoluteString.contains("\n"))
        #expect(url.absoluteString.contains("%0A"))
        let decodedBody = try makeParts(subject: "Subject", intro: "Intro").body
        #expect(decodedBody.contains("\n"))
    }

    @Test("An `&` in the subject or intro does not terminate the value")
    func ampersandSurvivesIntact() throws {
        let parts = try makeParts(subject: "Bug & crash", intro: "Included & sent:")
        #expect(parts.subject == "Bug & crash")
        #expect(parts.body.contains("Included & sent:"))
        // The literal `&` must be escaped in the URL, or the body would be cut
        // short at the first one and the rest read as another query item.
        #expect(parts.body.contains("Device: iPhone17,1"))
    }

    @Test("Nothing beyond the four declared fields ends up in the mail")
    func bodyCarriesNoUserData() throws {
        let parts = try makeParts()
        let block = parts.body.components(separatedBy: "\n").filter { !$0.isEmpty }
        // Intro + exactly four diagnostic lines: any additional line would be an
        // undeclared field, which is what the privacy exclusion list forbids.
        #expect(block.count == 5)
    }
}
