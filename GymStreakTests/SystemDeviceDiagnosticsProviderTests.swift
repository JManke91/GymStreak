//
//  SystemDeviceDiagnosticsProviderTests.swift
//  GymStreakTests
//
//  The metadata gateway behind the Settings support mail. Runs in the app host,
//  so it reads the real bundle and the real simulator environment — which is the
//  only automated way to catch the `hw.machine` trap (it reports the *host Mac's*
//  architecture, not the simulated device).
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct SystemDeviceDiagnosticsProviderTests {

    private let diagnostics = SystemDeviceDiagnosticsProvider().current

    @Test("Bundle fields are read, not left at the unknown placeholder")
    func bundleFields() {
        #expect(diagnostics.appVersion != "unknown")
        #expect(diagnostics.buildNumber != "unknown")
        #expect(!diagnostics.appVersion.isEmpty)
    }

    @Test("The OS version is the structured major.minor form")
    func systemVersion() throws {
        let major = try #require(diagnostics.systemVersion.split(separator: ".").first)
        #expect(Int(major) == ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    @Test("Locale is reported")
    func locale() {
        #expect(diagnostics.localeIdentifier == Locale.current.identifier)
    }

    #if targetEnvironment(simulator)
    /// On the simulator `sysctlbyname("hw.machine")` answers with the host Mac's
    /// architecture, so the provider must prefer `SIMULATOR_MODEL_IDENTIFIER`.
    @Test("Device model is the simulated device, not the host architecture")
    func deviceModelOnSimulator() {
        #expect(diagnostics.deviceModel != "arm64")
        #expect(diagnostics.deviceModel != "x86_64")
        #expect(diagnostics.deviceModel != "unknown")
        #expect(
            diagnostics.deviceModel
                == ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        )
    }
    #endif
}
