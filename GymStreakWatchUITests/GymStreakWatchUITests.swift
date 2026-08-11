//
//  GymStreakWatchUITests.swift
//  GymStreakWatchUITests
//
//  UI tests for automated Apple Watch App Store screenshot generation
//

import XCTest

/// Localized strings for watch UI tests.
/// Uses Fastlane's device language when available via Snapshot helper.
@MainActor
private enum LocalizedStrings {
    private static var isGerman: Bool {
        let fastlaneLanguage = Snapshot.deviceLanguage.lowercased()
        if !fastlaneLanguage.isEmpty {
            return fastlaneLanguage.hasPrefix("de")
        }
        return Locale.current.language.languageCode?.identifier == "de"
    }

    static var pushDay: String { isGerman ? "Drücken-Tag" : "Push Day" }
    static var benchPress: String { isGerman ? "Bankdrücken" : "Bench Press" }
    // XCUITest matches on the rendered accessibility label, so these have to be
    // the localized strings — the English literals never matched in de-DE and
    // silently stalled the German run after the routine-detail screen.
    static var startWorkout: String { isGerman ? "Workout starten" : "Start Workout" }
    static var endWorkout: String { isGerman ? "Workout beenden" : "End Workout" }
    static var skip: String { isGerman ? "Überspringen" : "Skip" }
    /// The invariant part of the Complete button's "Complete set 1 of 4" /
    /// "Satz 1 von 4 abschließen" accessibility label.
    static var completeSet: String { isGerman ? "abschließen" : "Complete set" }
}

@MainActor
final class GymStreakWatchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-UI_TESTING", "1", "-DISABLE_NOTIFICATIONS", "1"]

        setupSnapshot(app)
        app.launch()

        // Wait for data seeding and UI to settle
        sleep(3)
        let _ = app.wait(for: .runningForeground, timeout: 5)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Dark Mode Screenshots

    func testGenerateWatchScreenshotsDarkMode() throws {
        // 01: Routine List
        captureRoutineListScreen()

        // 02: Routine Detail
        captureRoutineDetailScreen()

        // 03: Active Workout Exercise List
        captureActiveWorkoutScreen()

        // 04: Set Editor
        captureSetEditorScreen()
    }

    // MARK: - Small-Screen Layout

    /// Regression guard for the 40 mm overflow: the set editor's Complete
    /// button and the rest timer's Skip button used to be laid out below the
    /// bottom edge on the smallest case, because the size tier was picked from
    /// the screen WIDTH and its smallest column was the design's 41 mm frame.
    /// Run this on `Apple Watch SE 3 (40mm)` — on a larger case it passes
    /// trivially.
    ///
    /// Not part of `testGenerateWatchScreenshotsDarkMode`: the App Store
    /// screenshot set must stay exactly the four release screens.
    func testControlsStayOnScreenOnSmallestCase() throws {
        captureRoutineDetailScreen()
        captureActiveWorkoutScreen()
        captureSetEditorScreen()

        let screen = app.frame

        let completeButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", LocalizedStrings.completeSet))
            .firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5), "Complete button should exist in the set editor")
        assertOnScreen(completeButton, in: screen, name: "Complete button")

        snapshot("90-Watch-Set-Editor-small")

        // Completing a set starts the rest timer (the seeded sets all carry a
        // restTime), which is the second screen that overflowed.
        completeButton.tap()
        sleep(2)

        let skipButton = app.buttons[LocalizedStrings.skip]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Rest timer Skip button should exist")
        assertOnScreen(skipButton, in: screen, name: "Rest timer Skip button")

        snapshot("91-Watch-Rest-Timer-small")
    }

    private func assertOnScreen(_ element: XCUIElement, in screen: CGRect, name: String) {
        let frame = element.frame
        XCTAssertTrue(
            screen.contains(frame),
            "\(name) is not fully on screen — frame \(frame) exceeds \(screen)"
        )
    }

    // MARK: - Screenshot Capture Methods

    private func captureRoutineListScreen() {
        // App launches directly to RoutineListView
        let pushDay = app.staticTexts[LocalizedStrings.pushDay]
        XCTAssertTrue(pushDay.waitForExistence(timeout: 10), "Push Day routine should be visible")

        sleep(1)
        snapshot("01-Watch-Routine-List-dark")
    }

    private func captureRoutineDetailScreen() {
        // Tap Push Day to navigate to RoutineDetailView
        let pushDay = app.staticTexts[LocalizedStrings.pushDay]
        XCTAssertTrue(pushDay.waitForExistence(timeout: 5), "Push Day should exist")
        pushDay.tap()

        // Wait for exercise list to appear
        let benchPress = app.staticTexts[LocalizedStrings.benchPress]
        XCTAssertTrue(benchPress.waitForExistence(timeout: 5), "Bench Press should be visible")

        sleep(1)
        snapshot("02-Watch-Routine-Detail-dark")
    }

    private func captureActiveWorkoutScreen() {
        // The Start Workout button is in the safeAreaInset at the bottom.
        // On watchOS carousel list, we need to scroll down or find it.
        // Try tapping the button directly first - it should be a button containing "Start Workout" text
        let startButton = app.buttons[LocalizedStrings.startWorkout]
        if !startButton.waitForExistence(timeout: 3) {
            // Try scrolling down to find the button
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Workout button should be visible")
        startButton.tap()

        // Wait for fullScreenCover to present and workout to initialize
        // The mock HealthKit sets workoutState = .running immediately,
        // but the fullScreenCover animation takes time
        sleep(5)

        // The ExerciseListView should now show exercise rows with the "End Workout" button
        let endWorkout = app.buttons[LocalizedStrings.endWorkout]
        if !endWorkout.waitForExistence(timeout: 10) {
            // If End Workout isn't visible, the fullScreenCover may not have presented.
            // Try waiting longer.
            sleep(3)
        }

        // Look for exercise name in the workout view
        let benchPress = app.staticTexts[LocalizedStrings.benchPress]
        XCTAssertTrue(benchPress.waitForExistence(timeout: 10), "Bench Press should be visible in workout")

        snapshot("03-Watch-Active-Workout-dark")
    }

    private func captureSetEditorScreen() {
        // Tap first exercise row to navigate to FullScreenSetEditorView
        // ExerciseRow uses .accessibilityElement(children: .combine), so the row is a single
        // accessibility element with label like "Bench Press, Not started, 0 of 4 sets completed"
        // Query for buttons containing the exercise name
        let exerciseRowPredicate = NSPredicate(format: "label CONTAINS %@", LocalizedStrings.benchPress)
        let exerciseRow = app.buttons.matching(exerciseRowPredicate).firstMatch
        XCTAssertTrue(exerciseRow.waitForExistence(timeout: 5), "Bench Press exercise row should be visible")
        exerciseRow.tap()

        // Wait for FullScreenSetEditorView to appear with WEIGHT/REPS editors
        sleep(3)

        // Verify we're in the set editor by checking for weight/reps labels
        let weightLabel = app.staticTexts["WEIGHT"]
        if !weightLabel.waitForExistence(timeout: 5) {
            // If WEIGHT label not found, try tapping the exercise row again
            // (the first tap may have been consumed by the accessibility system)
            if exerciseRow.exists {
                exerciseRow.tap()
                sleep(3)
            }
        }

        snapshot("04-Watch-Set-Editor-dark")
    }
}
