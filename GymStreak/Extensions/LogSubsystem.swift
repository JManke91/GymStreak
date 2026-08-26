//
//  LogSubsystem.swift
//  GymStreak
//
//  OSLog subsystem identifiers. Cross-layer by nature — a failure in Data and
//  the ViewModel failure it causes have to land under the same Console filter,
//  which only holds if the string is written once. See docs/settings-tab.md §4.2a.
//

import Foundation

enum LogSubsystem {
    /// Everything about getting the user's data out of this device and back:
    /// CloudKit mirroring and the local saves that feed it.
    static let sync = "app.gymstreak.sync"
}
