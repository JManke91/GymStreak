//
//  SwipeToDeleteUITests.swift
//  GymStreakUITests
//
//  Regression coverage for the history list's swipe-to-delete gesture.
//
//  These live in the UI test target because the behaviour under test is gesture
//  arbitration — whether a horizontal swipe also counts as a tap — which no unit
//  test can observe. The bug this guards against shipped once: the cards were
//  `NavigationLink`s, and a SwiftUI button activates on touch-up anywhere inside
//  its bounds, so every swipe pushed the detail screen before the revealed
//  delete action could be tapped.
//

import XCTest

@MainActor
final class SwipeToDeleteUITests: XCTestCase {
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

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]
        app.launch()
        dismissSystemAlerts()
        _ = app.wait(for: .runningForeground, timeout: 10)
        dismissCoachOptIn()
    }

    override func tearDownWithError() throws {
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
    ///
    /// The card is one combined accessibility element carrying the `.isButton`
    /// trait, so its label includes the routine name alongside the date and metrics.
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

    /// The regression: a swipe must reveal delete and must NOT navigate.
    func testSwipingCardRevealsDeleteWithoutNavigating() throws {
        let card = try firstWorkoutCard()

        card.swipeLeft()

        let deleteAction = app.buttons[deleteLabel]
        XCTAssertTrue(
            deleteAction.waitForExistence(timeout: 3),
            "Swiping a card left should reveal the delete action"
        )
        XCTAssertFalse(
            app.buttons[detailMenuLabel].exists,
            "Swiping must not push the workout detail screen"
        )
    }

    /// The revealed action must reach the same confirmation the detail screen uses.
    func testRevealedDeleteOpensConfirmation() throws {
        let card = try firstWorkoutCard()

        card.swipeLeft()

        let deleteAction = app.buttons[deleteLabel]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 3), "Delete action should be revealed")
        deleteAction.tap()

        let alert = app.alerts[confirmationTitle]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 3),
            "Triggering the revealed delete should raise the shared delete confirmation"
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

    /// The list cards push onto a `NavigationPath`, so the other destinations on the
    /// same stack have to keep working — the settings screen was converted from an
    /// `isPresented` push for exactly that reason.
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
