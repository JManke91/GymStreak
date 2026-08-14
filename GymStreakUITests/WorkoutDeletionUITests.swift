//
//  WorkoutDeletionUITests.swift
//  GymStreakUITests
//
//  Regression coverage for workout deletion entry points and History navigation.
//

import XCTest

@MainActor
final class WorkoutDeletionUITests: XCTestCase {
    private var app: XCUIApplication!

    private var isGerman: Bool {
        Locale.current.language.languageCode?.identifier == "de"
    }

    /// UI tests can't read the app's Localizable.strings, so the expected copy is replicated.
    private var historyTab: String { isGerman ? "Verlauf" : "History" }
    private var seededRoutineName: String { isGerman ? "Drücken-Tag" : "Push Day" }
    private var deleteLabel: String { isGerman ? "Löschen" : "Delete" }
    private var detailMenuLabel: String { isGerman ? "Mehr" : "More" }
    private var confirmationTitle: String { isGerman ? "Workout löschen?" : "Delete Workout?" }
    private var coachOptInDismiss: String { isGerman ? "Vielleicht später" : "Maybe later" }
    private var coachSettingsLabel: String { isGerman ? "AI Coach Einstellungen" : "AI Coach settings" }
    /// A row title unique to the settings screen (the section headers are uppercased).
    private var coachSettingsRow: String { isGerman ? "Nach jedem Workout" : "After each workout" }

    // `setUp() async throws` rather than `setUpWithError() throws`: the throwing
    // synchronous variant overrides a `nonisolated` XCTest method, and an override
    // must match its superclass's isolation — which strips this class's `@MainActor`
    // and makes every `XCUIApplication` touch a cross-actor reference. The `async`
    // variant inherits the class isolation correctly.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UI_TESTING", "1",
            "-UI_TEST_EPHEMERAL_STORE", "1",
            "-DISABLE_NOTIFICATIONS", "1"
        ]
        app.launch()
        dismissSystemAlerts()
        _ = app.wait(for: .runningForeground, timeout: 10)
        dismissCoachOptIn()
    }

    override func tearDown() async throws {
        app = nil
    }

    /// The AI Coach opt-in prompt covers the UI on a fresh launch and swallows taps.
    private func dismissCoachOptIn() {
        let dismiss = app.buttons[coachOptInDismiss]
        if dismiss.waitForExistence(timeout: 5) { dismiss.tap() }
    }

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    /// The first seeded workout card in the Trainings list.
    private func firstWorkoutCard() throws -> XCUIElement {
        let historyTabButton = app.tabBars.buttons[historyTab]
        XCTAssertTrue(historyTabButton.waitForExistence(timeout: 10), "History tab should exist")
        historyTabButton.tap()
        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", seededRoutineName))
            .firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 15),
            "Seeded workout card should be visible in the history list"
        )
        return card
    }

    /// The list keeps deletion available without attaching a horizontal drag recognizer
    /// to every row. The long-press menu is the shortcut; the detail screen also has
    /// an always-visible More menu.
    func testLongPressCardOffersDeleteWithoutNavigating() throws {
        let card = try firstWorkoutCard()

        card.press(forDuration: 1.2)

        let deleteAction = app.buttons[deleteLabel]
        XCTAssertTrue(
            deleteAction.waitForExistence(timeout: 3),
            "Long-pressing a card should offer the delete action"
        )
        XCTAssertFalse(
            app.buttons[detailMenuLabel].exists,
            "Opening the context menu must not push the workout detail screen"
        )
    }

    /// The context-menu shortcut must reach the same confirmation as the detail screen.
    func testContextMenuDeleteOpensConfirmation() throws {
        let card = try firstWorkoutCard()

        card.press(forDuration: 1.2)

        let deleteAction = app.buttons[deleteLabel]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 3), "Delete action should be offered")
        deleteAction.tap()

        let alert = app.alerts[confirmationTitle]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 3),
            "Context-menu deletion should raise the shared delete confirmation"
        )
    }

    /// The gesture must not cost the plain tap: tapping a card still opens it.
    func testTappingCardStillNavigatesToDetail() throws {
        let card = try firstWorkoutCard()

        card.tap()

        XCTAssertTrue(
            app.buttons[detailMenuLabel].waitForExistence(timeout: 5),
            "Tapping a card should push the workout detail screen"
        )
    }

    /// The path-bound stack must keep its other destination types working.
    func testCoachSettingsStillPushesOnThePathBoundStack() throws {
        let historyTabButton = app.tabBars.buttons[historyTab]
        XCTAssertTrue(historyTabButton.waitForExistence(timeout: 10), "History tab should exist")
        historyTabButton.tap()

        let settingsButton = app.buttons[coachSettingsLabel]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Settings button should exist")
        settingsButton.tap()

        XCTAssertTrue(
            app.staticTexts[coachSettingsRow].waitForExistence(timeout: 5),
            "The gear button should push the AI Coach settings screen"
        )
    }
}
