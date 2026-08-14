//
//  SettingsTabUITests.swift
//  GymStreakUITests
//

import XCTest

@MainActor
final class SettingsTabUITests: XCTestCase {

    private var isGerman: Bool {
        // watchOS/iOS simulators don't always honour -AppleLanguages in Locale.current.
        let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        let code = languages?.first ?? Locale.current.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("de")
    }

    func testSettingsRowPushesAICoachSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]
        app.launch()

        // Dismiss the AI Coach opt-in cover if it appears.
        let maybeLater = app.buttons[isGerman ? "Vielleicht später" : "Maybe later"]
        if maybeLater.waitForExistence(timeout: 8) {
            maybeLater.tap()
        }

        let settingsTab = app.tabBars.buttons[isGerman ? "Einstellungen" : "Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab missing")
        settingsTab.tap()

        let row = app.buttons["settings-row-ai-coach"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "AI Coach row missing")
        row.tap()

        // The master toggle row is unique to AICoachSettingsView.
        let masterToggle = app.staticTexts[isGerman ? "Coach aktivieren" : "Enable Coach"]
        XCTAssertTrue(
            masterToggle.waitForExistence(timeout: 5),
            "AI Coach settings screen was not pushed"
        )
    }

    /// The Support section's "Rate app" row. Only its presence and tap target are
    /// asserted — the App Store app does not exist on the simulator, so where the
    /// deep link lands can only be verified on a device.
    func testSupportSectionShowsRateAppRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]
        app.launch()

        let maybeLater = app.buttons[isGerman ? "Vielleicht später" : "Maybe later"]
        if maybeLater.waitForExistence(timeout: 8) {
            maybeLater.tap()
        }

        let settingsTab = app.tabBars.buttons[isGerman ? "Einstellungen" : "Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab missing")
        settingsTab.tap()

        let row = app.buttons["settings-row-rate-app"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Rate app row missing")
        XCTAssertTrue(row.isHittable, "Rate app row is not tappable")

        let title = isGerman ? "App bewerten" : "Rate app"
        XCTAssertTrue(row.label.contains(title), "Unexpected row label: \(row.label)")
    }

    /// The "Contact support" row's fallback path. The simulator ships no mail
    /// client, so `openURL` reports the `mailto:` URL as unaccepted — exactly the
    /// state the alert exists for. The primary path (a mail app opening on the
    /// prefilled message) can only be verified on a device.
    func testContactSupportRowFallsBackToCopyableAddress() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]
        app.launch()

        let maybeLater = app.buttons[isGerman ? "Vielleicht später" : "Maybe later"]
        if maybeLater.waitForExistence(timeout: 8) {
            maybeLater.tap()
        }

        let settingsTab = app.tabBars.buttons[isGerman ? "Einstellungen" : "Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab missing")
        settingsTab.tap()

        let row = app.buttons["settings-row-contact-support"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Contact support row missing")
        let title = isGerman ? "Support kontaktieren" : "Contact support"
        XCTAssertTrue(row.label.contains(title), "Unexpected row label: \(row.label)")
        row.tap()

        let alert = app.alerts[isGerman ? "Keine Mail-App" : "No mail app"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 5),
            "No mail client on the simulator should surface the fallback alert"
        )
        XCTAssertTrue(
            alert.staticTexts.element(boundBy: 1).label.contains("julian.manke@googlemail.com"),
            "Fallback alert should show the support address"
        )
        alert.buttons[isGerman ? "Adresse kopieren" : "Copy address"].tap()
    }

    /// The simulator has no iCloud account (and the CloudKit store may fall back to
    /// local-only), so the Data section must report the "off" state rather than a
    /// stale "up to date".
    func testICloudRowReportsOffWithoutICloudAccount() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]
        app.launch()

        let maybeLater = app.buttons[isGerman ? "Vielleicht später" : "Maybe later"]
        if maybeLater.waitForExistence(timeout: 8) {
            maybeLater.tap()
        }

        let settingsTab = app.tabBars.buttons[isGerman ? "Einstellungen" : "Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab missing")
        settingsTab.tap()

        // The row combines its children into one accessibility element.
        let row = app.descendants(matching: .any)["settings-row-icloud"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "iCloud row missing")

        // The account status is queried asynchronously at launch, so the row can
        // still show its optimistic initial state for a moment.
        let offLabel = isGerman ? "Aus" : "Off"
        let notSynced = isGerman ? "Nicht synchronisiert" : "Not synced"
        let reportsOff = NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", offLabel, notSynced
        )
        // `fulfillment(of:timeout:)` rather than `waitForExpectations(timeout:handler:)`:
        // the completion handler is a nonisolated closure, so reading the
        // main-actor-isolated `row.label` inside it for the failure message is a
        // cross-actor access. Awaiting the expectation keeps the assertion — and
        // the label read — on this `@MainActor` test method.
        let expectation = expectation(for: reportsOff, evaluatedWith: row)
        await fulfillment(of: [expectation], timeout: 10)
        XCTAssertTrue(
            reportsOff.evaluate(with: row),
            "iCloud row should report the off state, got: \(row.label)"
        )
    }
}
