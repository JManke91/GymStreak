//
//  SystemDeviceDiagnosticsProvider.swift
//  GymStreak
//
//  Reads the bundle/OS/hardware metadata prefilled into a support mail.
//  The only place in the app allowed to touch `Bundle`, `ProcessInfo` or
//  `sysctlbyname` for this purpose. See docs/settings-tab.md.
//

import Foundation

struct SystemDeviceDiagnosticsProvider: DeviceDiagnosticsProviding {

    /// Shown instead of a value that could not be read — never an empty line,
    /// so a missing field is visible in the mail rather than silently absent.
    private static let unknown = "unknown"

    var current: DeviceDiagnostics {
        DeviceDiagnostics(
            appVersion: Self.infoValue(for: "CFBundleShortVersionString"),
            buildNumber: Self.infoValue(for: "CFBundleVersion"),
            systemVersion: Self.systemVersion,
            deviceModel: Self.deviceModel,
            localeIdentifier: Locale.current.identifier
        )
    }

    private static func infoValue(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? unknown
    }

    /// `ProcessInfo`'s structured version rather than `UIDevice.systemVersion`:
    /// the free-form string carries no guarantee about its shape.
    private static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
    }

    /// The hardware identifier, e.g. `iPhone17,1`.
    ///
    /// `UIDevice.current.model` is unusable here — it returns only the generic
    /// `"iPhone"`. On the simulator `hw.machine` reports the *host Mac's*
    /// architecture (`arm64`), so the simulated device's real identifier is read
    /// from the environment first.
    private static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return unknown
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else {
            return unknown
        }
        let identifier = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return identifier.isEmpty ? unknown : identifier
    }
}
