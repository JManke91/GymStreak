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

    /// The simulator has no iCloud account (and the CloudKit store may fall back to
    /// local-only), so the Data section must report the "off" state rather than a
    /// stale "up to date".
    func testICloudRowReportsOffWithoutICloudAccount() throws {
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
        expectation(for: reportsOff, evaluatedWith: row)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(
                error,
                "iCloud row should report the off state, got: \(row.label)"
            )
        }
    }
}
