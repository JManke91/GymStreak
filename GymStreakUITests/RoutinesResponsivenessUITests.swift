//
//  RoutinesResponsivenessUITests.swift
//  GymStreakUITests
//
//  Regression coverage for the Routinen tab's main-thread rendering cost. The screen used to
//  build every card the user owns before the first frame (eager `VStack`) and to derive each
//  card's metrics inside `body` — the same two rules the History tab broke. The routine count
//  is unbounded for Pro users, so this launches with a 40-routine library rather than the
//  free-tier three. Method and probe from docs/history-performance.md §5.
//

import XCTest

@MainActor
final class RoutinesResponsivenessUITests: XCTestCase {
    private var app: XCUIApplication!

    /// `setUp() async throws` rather than `setUpWithError() throws` — see
    /// `HistoryResponsivenessUITests` for why the throwing synchronous variant strips
    /// this class's `@MainActor`.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UI_TESTING", "1",
            "-UI_TEST_EPHEMERAL_STORE", "1",
            "-UI_TEST_ROUTINE_COUNT", "40",
            "-UI_TEST_STALL_PROBE", "1",
            "-DISABLE_NOTIFICATIONS", "1",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        dismissCoachOptIn()
    }

    override func tearDown() async throws {
        app = nil
    }

    func testRoutinesListDoesNotBlockMainRunLoop() {
        let stallProbe = app.staticTexts["routines-main-thread-max-delay-ms"]
        XCTAssertTrue(stallProbe.waitForExistence(timeout: 10))

        // Measured across a tab round trip rather than from launch: Routines is the
        // initial tab, so a launch-anchored figure would be dominated by seeding 40
        // routines into SwiftData. Re-entering resets the probe on `onAppear` and
        // measures what a user actually pays — `fetchRoutines()` plus the first frame.
        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()

        let routines = app.tabBars.buttons["Routines"]
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        routines.tap()

        assertNoMainThreadStall(
            stallProbe,
            action: "opening Routines with 40 routines",
            thresholdMilliseconds: 250
        )

        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        assertNoMainThreadStall(
            stallProbe,
            action: "scrolling the routines list",
            thresholdMilliseconds: 150
        )
    }

    /// The same click path with calendar sync switched on and every one of the 40
    /// routines planned — the shape ticket 03's reconcile hook added to this
    /// screen (docs/calendar-sync.md §12).
    ///
    /// The opt-in is flipped through `NSArgumentDomain` rather than through the
    /// Settings toggle, which keeps this a pure measurement: no production code
    /// knows it is under test, and no Calendar permission prompt appears. What it
    /// therefore measures is everything the mirror pays on **every** pass — the
    /// routine fetch, one `lastCompletedStartDates` lookup per routine and 40
    /// cadence walks — which is the half that scales with the user's library. The
    /// EventKit round-trip is the half a simulator cannot represent (there is no
    /// CalDAV-backed store behind it) and is verified on device instead.
    func testRoutinesListWithCalendarSyncEnabled() {
        app.terminate()
        app.launchArguments += [
            "-UI_TEST_PLAN_ROUTINES",
            "-calendar_sync.enabled", "YES"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        dismissCoachOptIn()

        let stallProbe = app.staticTexts["routines-main-thread-max-delay-ms"]
        XCTAssertTrue(stallProbe.waitForExistence(timeout: 10))

        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()

        let routines = app.tabBars.buttons["Routines"]
        XCTAssertTrue(routines.waitForExistence(timeout: 5))
        routines.tap()

        assertNoMainThreadStall(
            stallProbe,
            action: "opening Routines with 40 planned routines and calendar sync on",
            thresholdMilliseconds: 250
        )
    }

    /// Context menus on lazily-materialized rows are a documented fragile corner of SwiftUI
    /// (a window-attachment race that crashes with "UIPreviewTarget requires that the container
    /// view is in a window"). The reports involve nested lazy stacks, which this screen does not
    /// have — this smoke test is what keeps that true after the `VStack` → `LazyVStack` move,
    /// on a row the lazy stack materialized during scrolling rather than before the first frame.
    func testContextMenuOnAScrolledRoutineRow() {
        let routines = app.tabBars.buttons["Routines"]
        XCTAssertTrue(routines.waitForExistence(timeout: 10))

        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Routine ")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.2)

        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(
            duplicate.waitForExistence(timeout: 5),
            "the context menu did not open on a lazily materialized routine row"
        )
        // Dismiss without acting: this test is about the menu opening, not about duplication.
        app.tap()
    }

    private func assertNoMainThreadStall(
        _ probe: XCUIElement,
        action: String,
        thresholdMilliseconds: Int
    ) {
        let rawValue = probe.value as? String
        let displayedValue = rawValue ?? probe.label
        let delay = Int(displayedValue.filter(\.isNumber)) ?? .max
        // Recorded as an activity as well as asserted: the before/after comparison in
        // docs/history-performance.md is read out of the result bundle, and a passing
        // assertion prints nothing.
        XCTContext.runActivity(named: "[stall-probe] \(action): \(delay) ms") { _ in }
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
