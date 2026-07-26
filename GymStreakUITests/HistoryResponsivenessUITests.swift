//
//  HistoryResponsivenessUITests.swift
//  GymStreakUITests
//
//  Regression coverage for the History tab's release-blocking main-thread stalls.
//

import XCTest

@MainActor
final class HistoryResponsivenessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UI_TESTING", "1",
            "-UI_TEST_EPHEMERAL_STORE", "1",
            "-UI_TEST_HISTORY_SESSION_COUNT", "60",
            "-UI_TEST_HISTORY_STALL_PROBE", "1",
            "-DISABLE_NOTIFICATIONS", "1",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        dismissCoachOptIn()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testHistoryInteractionsDoNotBlockMainRunLoop() {
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10))
        historyTab.tap()

        let stallProbe = app.staticTexts["history-main-thread-max-delay-ms"]
        XCTAssertTrue(stallProbe.waitForExistence(timeout: 5))
        assertNoMainThreadStall(
            stallProbe,
            action: "opening History",
            thresholdMilliseconds: 400
        )

        let progress = app.buttons["history-section-fortschritt"]
        XCTAssertTrue(progress.waitForExistence(timeout: 2))
        progress.tap()

        let workouts = app.buttons["history-section-trainings"]
        XCTAssertTrue(workouts.waitForExistence(timeout: 2))
        workouts.tap()
        assertNoMainThreadStall(
            stallProbe,
            action: "switching Fortschritt to Trainings",
            thresholdMilliseconds: 250
        )

        app.swipeUp(velocity: .fast)
        assertNoMainThreadStall(
            stallProbe,
            action: "scrolling Trainings",
            thresholdMilliseconds: 150
        )
    }

    private func assertNoMainThreadStall(
        _ probe: XCUIElement,
        action: String,
        thresholdMilliseconds: Int
    ) {
        let rawValue = probe.value as? String
        let displayedValue = rawValue ?? probe.label
        let delay = Int(displayedValue.filter(\.isNumber)) ?? .max
        XCTAssertLessThan(
            delay,
            thresholdMilliseconds,
            "\(action) delayed the main run loop by \(delay) ms "
                + "(value: \(rawValue ?? "nil"), label: \(probe.label))"
        )
    }

    private func dismissCoachOptIn() {
        let dismiss = app.buttons["Maybe later"]
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }
    }
}
