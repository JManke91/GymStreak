//
//  WatchAppDelegate.swift
//  GymStreakWatch Watch App
//
//  Ticket 08 (in-workout routine editing): wires watchOS active-workout
//  recovery into the SwiftUI app lifecycle.
//
//  `handleActiveWorkoutRecovery()` is the documented crash-relaunch signal
//  (declared on the modern `WKApplicationDelegate`, not the deprecated
//  `WKExtensionDelegate`). It is NOT guaranteed after a normal force-quit and
//  is reported as not firing after a watch reboot, so recovery is also kicked
//  defensively from `applicationDidFinishLaunching()`. Both funnel into the
//  idempotent `WatchWorkoutRecoveryCoordinator`, which performs the actual
//  recovery once per process and buffers the request until the live components
//  are registered by `AppState`.
//

import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchWorkoutRecoveryCoordinator.shared.recoverIfNeeded()
    }

    func handleActiveWorkoutRecovery() {
        WatchWorkoutRecoveryCoordinator.shared.recoverIfNeeded()
    }
}
