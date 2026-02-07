//
//  GymStreakUITests.swift
//  GymStreakUITests
//
//  UI tests for automated App Store screenshot generation
//

import XCTest

/// Localized strings - uses Fastlane's device language when available
/// Note: UI tests can't access main app's Localizable.strings, so we replicate the values here
@MainActor
private enum LocalizedStrings {
    private static var isGerman: Bool {
        // Check Fastlane's device language first (set via language.txt)
        let fastlaneLanguage = Snapshot.deviceLanguage.lowercased()
        if !fastlaneLanguage.isEmpty {
            return fastlaneLanguage.hasPrefix("de")
        }
        // Fallback to system locale for direct xcodebuild runs
        return Locale.current.language.languageCode?.identifier == "de"
    }

    // Test data names
    static var pushDay: String { isGerman ? "Drücken-Tag" : "Push Day" }
    static var benchPress: String { isGerman ? "Bankdrücken" : "Bench Press" }

    // Tab names
    static var routinesTab: String { isGerman ? "Routinen" : "Routines" }
    static var historyTab: String { isGerman ? "Verlauf" : "History" }
    static var exercisesTab: String { isGerman ? "Übungen" : "Exercises" }

    // Buttons
    static var startWorkout: String { isGerman ? "Workout starten" : "Start Workout" }
}

@MainActor
final class GymStreakUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // UI testing flag + disable notification prompts
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]

        setupSnapshot(app)
        app.launch()

        // Dismiss any system alerts (like notification permissions)
        dismissSystemAlerts()

        // Wait for app to fully load and test data to seed
        sleep(2)

        // Wait for the first screen to appear
        let _ = app.wait(for: .runningForeground, timeout: 5)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Dismiss any system alerts that may appear
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Handle notification permission alert
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }

        // Also try "Don't Allow" as fallback
        let dontAllowButton = springboard.buttons["Don't Allow"]
        if dontAllowButton.waitForExistence(timeout: 1) {
            dontAllowButton.tap()
        }
    }

    // MARK: - Light Mode Screenshots

    func testGenerateScreenshots() throws {
        // Screenshot 1: Routines List
        captureRoutinesListScreen()

        // Screenshot 2: Routine Detail
        captureRoutineDetailScreen()

        // Screenshot 3: Active Workout
        captureActiveWorkoutScreen()

        // Screenshot 4: Workout History
        captureWorkoutHistoryScreen()

        // Screenshot 5: Exercise Library
        captureExerciseLibraryScreen()
    }

    // MARK: - Dark Mode Screenshots

    func testGenerateScreenshotsDarkMode() throws {
        // Screenshot 1: Routines List (Dark)
        captureRoutinesListScreen(suffix: "-dark")

        // Screenshot 2: Routine Detail (Dark)
        captureRoutineDetailScreen(suffix: "-dark")

        // Screenshot 3: Active Workout (Dark)
        captureActiveWorkoutScreen(suffix: "-dark")

        // Screenshot 4: Workout History (Dark)
        captureWorkoutHistoryScreen(suffix: "-dark")

        // Screenshot 5: Exercise Library (Dark)
        captureExerciseLibraryScreen(suffix: "-dark")
    }

    // MARK: - Screenshot Capture Methods

    private func captureRoutinesListScreen(suffix: String = "") {
        // Navigate to Routines tab first (in case we're not there)
        app.navigateToTab(LocalizedStrings.routinesTab)
        sleep(1)

        // Wait for routines to appear - look for localized "Push Day" which is seeded test data
        let pushDayCell = app.staticTexts[LocalizedStrings.pushDay]
        XCTAssertTrue(pushDayCell.waitForExistence(timeout: 10), "Push Day routine should be visible")

        // Capture screenshot
        takeScreenshot("01-Routines-List\(suffix)")
    }

    private func captureRoutineDetailScreen(suffix: String = "") {
        // Navigate to Routines tab first
        app.navigateToTab(LocalizedStrings.routinesTab)
        sleep(1)

        // Tap first routine (Push Day)
        let pushDayCell = app.staticTexts[LocalizedStrings.pushDay]
        XCTAssertTrue(pushDayCell.waitForExistence(timeout: 5), "Push Day should exist")
        pushDayCell.tap()

        // Wait for routine detail to load - look for localized exercise name
        let benchPress = app.staticTexts[LocalizedStrings.benchPress]
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5), "Bench Press exercise should be visible")

        // Give UI time to settle
        sleep(1)

        // Capture screenshot
        takeScreenshot("02-Routine-Detail\(suffix)")

        // Navigate back to routines list
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
            sleep(1)
        }
    }

    private func captureActiveWorkoutScreen(suffix: String = "") {
        // Navigate to Routines tab first
        app.navigateToTab(LocalizedStrings.routinesTab)
        sleep(1)

        // Tap first routine (Push Day)
        let pushDayCell = app.staticTexts[LocalizedStrings.pushDay]
        XCTAssertTrue(pushDayCell.waitForExistence(timeout: 5), "Push Day should exist")
        pushDayCell.tap()

        // Wait for routine detail to load
        let startWorkoutButton = app.buttons[LocalizedStrings.startWorkout]
        XCTAssertTrue(startWorkoutButton.waitForExistence(timeout: 5), "Start Workout button should be visible")

        // Start the workout
        startWorkoutButton.tap()
        sleep(2)

        // Dismiss any HealthKit authorization alerts
        dismissSystemAlerts()
        sleep(1)

        // Capture screenshot of active workout
        takeScreenshot("03-Active-Workout\(suffix)")

        // Cancel the workout to return to normal state
        // Look for cancel button in navigation bar
        let cancelButton = app.navigationBars.buttons.firstMatch
        if cancelButton.exists {
            cancelButton.tap()
            sleep(1)

            // Confirm cancel if there's a confirmation dialog
            let discardButton = app.buttons["Discard Workout"]
            if discardButton.waitForExistence(timeout: 2) {
                discardButton.tap()
                sleep(1)
            }

            // Try German version
            let verwerfenButton = app.buttons["Workout verwerfen"]
            if verwerfenButton.waitForExistence(timeout: 1) {
                verwerfenButton.tap()
                sleep(1)
            }
        }
    }

    private func captureWorkoutHistoryScreen(suffix: String = "") {
        // Navigate to History tab (localized)
        app.navigateToTab(LocalizedStrings.historyTab)
        sleep(2)

        // Wait for history to load - the seeded data includes workout sessions
        sleep(1)

        // Capture screenshot
        takeScreenshot("04-Workout-History\(suffix)")
    }

    private func captureExerciseLibraryScreen(suffix: String = "") {
        // Navigate to Exercises tab (localized)
        app.navigateToTab(LocalizedStrings.exercisesTab)
        sleep(2)

        // Wait for exercises to load - look for a localized seeded exercise
        let benchPress = app.staticTexts[LocalizedStrings.benchPress]
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5), "Bench Press exercise should be visible in library")

        // Capture screenshot
        takeScreenshot("05-Exercise-Library\(suffix)")
    }
}
