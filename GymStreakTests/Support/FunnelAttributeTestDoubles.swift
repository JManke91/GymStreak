//
//  FunnelAttributeTestDoubles.swift
//  GymStreakTests
//
//  The doubles behind `FunnelAttributeTests` (docs/funnel-instrumentation.md).
//  Shared here rather than kept file-private because the suite that uses them
//  is already at the file-size limit.
//

import Foundation
import StoreKit
@testable import GymStreak

/// Every report, in order. An array rather than a "last value" so a test can
/// assert that a failed read reported *nothing* — the case a single optional
/// could not tell from "reported zero".
@MainActor
final class SpyReporter: FunnelAttributeReporting {
    private(set) var reported: [FunnelAttributes] = []

    func report(_ attributes: FunnelAttributes) {
        reported.append(attributes)
    }
}

/// A `LifetimeTrainingTotalsProviding` whose count can move between reports.
/// An `actor` because the protocol is `Sendable`, as in `ReviewPromptTests`.
actor StubWorkoutCount: LifetimeTrainingTotalsProviding {
    private var count: Int
    private var isUnreachable = false

    init(_ count: Int) {
        self.count = count
    }

    func set(_ count: Int) { self.count = count }
    func setUnreachable(_ isUnreachable: Bool) { self.isUnreachable = isUnreachable }

    func fetchCompletedWorkoutCount() async throws -> Int {
        if isUnreachable { throw StubLookupFailure() }
        return count
    }

    /// Never called by the funnel coordinator — deliberately, since the
    /// whole-history walk shares the History model actor. A `fatalError` would
    /// be the louder assertion, but this suite would rather fail on the
    /// attribute than on a crash, so it returns something inert.
    func fetchLifetimeTotals() async throws -> LifetimeTrainingTotals {
        LifetimeTrainingTotals(workoutCount: count, completedSetCount: 0, volumeKilograms: 0)
    }
}

/// What `StubDownloads` answers with. Top-level rather than nested so it can be
/// passed as a `@Test(arguments:)` case, which requires a `Sendable` type
/// outside any actor.
enum StubDownloadOutcome: Sendable {
    case download(OriginalAppDownload)
    /// Offline, or not signed in to the App Store.
    case failure
}

/// Stands in for StoreKit, which offers no way to build an `AppTransaction`:
/// the type has no public initializer, so this seam is the only way to reach
/// the environment branches from a unit test. The same shape
/// `FounderStatusTests` declares privately for its own suite.
@MainActor
final class StubDownloads: OriginalAppDownloadReading {

    var outcome: StubDownloadOutcome
    private(set) var callCount = 0

    init(_ outcome: StubDownloadOutcome) {
        self.outcome = outcome
    }

    func originalAppDownload() async throws -> OriginalAppDownload {
        callCount += 1
        switch outcome {
        case .download(let download): return download
        case .failure: throw StubLookupFailure()
        }
    }
}

struct StubLookupFailure: Error {}
