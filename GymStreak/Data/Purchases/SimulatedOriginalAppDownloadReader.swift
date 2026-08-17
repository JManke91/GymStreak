//
//  SimulatedOriginalAppDownloadReader.swift
//  GymStreak
//
//  Debug-only stand-in for StoreKit's record of the original app download, so
//  the Founder decision can be exercised on a device at all.
//  See docs/pro-subscription.md §9.4c.
//

#if DEBUG
import Foundation
import StoreKit

/// Returns a fixed `OriginalAppDownload` instead of asking StoreKit.
///
/// **Why this has to exist.** The Founder grant refuses to decide unless
/// `AppTransaction.environment == .production` (§7.1 trap 2, and the guard is
/// load-bearing: without it every TestFlight tester would be granted Pro
/// forever). A TestFlight install reports `.sandbox` and an Xcode install
/// reports `.xcode`, so *no* pre-release install can ever produce a grant —
/// which left the whole path from decision to thank-you screen unexercised on
/// hardware, verified only by unit tests against the `OriginalAppDownloadReading`
/// projection. This is that projection's other implementation, selected by a
/// launch argument, and it makes the real `FounderStatusService`, the real
/// persistence and the real celebration run on a device.
///
/// It deliberately does **not** relax the environment guard. It replaces the
/// *reader*, so the guard, the `Int` parse and the `< cutoffBuild` comparison
/// all still run exactly as they will in production — the only thing faked is
/// the value Apple would have returned.
struct SimulatedOriginalAppDownloadReader: OriginalAppDownloadReading {

    /// Simulates an install that predates monetization: every shipped
    /// pre-cutoff build reported `"1"` (§7.1 trap 5). Expect a grant.
    static let preCutoffArgument = "-FOUNDER_SIMULATE_PRECUTOFF"

    /// Simulates an install at the cutoff itself. Expect **no** grant — the
    /// comparison is strictly less-than, so the cutoff build never grants, and
    /// this is the boundary worth walking on device rather than a value safely
    /// past it.
    static let cutoffArgument = "-FOUNDER_SIMULATE_CUTOFF"

    /// Where a simulated run's decision is written.
    ///
    /// A separate suite, wiped at the start of every simulated launch by
    /// `AppDependencies`, so a debugging session can never write to the real
    /// `pro.isFounder` key. That matters more than it looks: the real decision
    /// is recorded **once and kept forever**, so a simulated grant landing in
    /// `UserDefaults.standard` would leave the device permanently claiming
    /// Founder with no gate in sight — indistinguishable from the app being
    /// broken, which is the §9.4b class of trap this whole area keeps producing.
    static let defaultsSuiteName = "pro.founder.simulated"

    let download: OriginalAppDownload

    /// The reader this run asked for, or `nil` for "use the real StoreKit one".
    static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Self? {
        if arguments.contains(preCutoffArgument) {
            return Self(download: .verified(environment: .production, originalAppVersion: "1"))
        }
        if arguments.contains(cutoffArgument) {
            return Self(
                download: .verified(
                    environment: .production,
                    originalAppVersion: String(FounderStatusService.cutoffBuild)
                )
            )
        }
        return nil
    }

    func originalAppDownload() async throws -> OriginalAppDownload {
        download
    }
}
#endif
