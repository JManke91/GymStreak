//
//  UITestHelpers.swift
//  GymStreakUITests
//
//  UI testing helper extensions for screenshot automation
//

import XCTest

extension XCUIApplication {
    /// Wait for an element to appear with timeout
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Wait for an element to disappear
    func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Navigate to specific tab by name
    func navigateToTab(_ tabName: String) {
        let tabBar = self.tabBars.firstMatch
        let tabButton = tabBar.buttons[tabName]
        if tabButton.waitForExistence(timeout: 5) {
            tabButton.tap()
        }
    }
}

extension XCTestCase {
    /// Takes a Fastlane snapshot with optional delay for UI settling
    /// - Parameters:
    ///   - name: The name of the screenshot
    ///   - delay: Time to wait before capturing (allows UI animations to complete)
    @MainActor
    func takeScreenshot(_ name: String, delay: TimeInterval = 0.5) {
        sleep(UInt32(delay))
        snapshot(name)
    }

    /// Takes a snapshot with custom idle timeout
    /// - Parameters:
    ///   - name: The name of the screenshot
    ///   - timeout: Amount of seconds to wait until network loading indicators disappear
    @MainActor
    func takeScreenshot(_ name: String, timeWaitingForIdle timeout: TimeInterval) {
        snapshot(name, timeWaitingForIdle: timeout)
    }
}
