//
//  DeviceDiagnosticsProviding.swift
//  GymStreak
//
//  Domain-facing view of the device/bundle metadata prefilled into a support
//  mail. Implemented in Data by `SystemDeviceDiagnosticsProvider` —
//  see docs/settings-tab.md.
//

import Foundation

/// The triage facts a support mail carries.
///
/// Deliberately narrow: nothing here identifies the user or their training.
/// No HealthKit value, workout/routine/exercise content, name, mail address,
/// iCloud or Sign-in-with-Apple identifier, UDID, serial number or location may
/// be added — none of it helps triage, and shipping health data out of the app
/// outside its stated purpose is an App Review 5.1.1 risk.
struct DeviceDiagnostics: Sendable, Equatable {
    /// `CFBundleShortVersionString`, e.g. `1.4.0`.
    let appVersion: String
    /// `CFBundleVersion`, e.g. `128`.
    let buildNumber: String
    /// Marketing OS version, e.g. `26.5` or `26.5.1`.
    let systemVersion: String
    /// Hardware identifier, e.g. `iPhone17,1` — never the generic `"iPhone"`.
    let deviceModel: String
    /// `Locale.current.identifier`, e.g. `de_DE`.
    let localeIdentifier: String
}

/// Reads device and bundle metadata. A system gateway, not view code: the
/// implementation is the only place allowed to touch `Bundle`, `ProcessInfo`
/// or `sysctlbyname`.
protocol DeviceDiagnosticsProviding: Sendable {
    /// Metadata as of now.
    var current: DeviceDiagnostics { get }
}
