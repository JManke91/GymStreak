//
//  FounderStatusTests.swift
//  GymStreakTests
//
//  The Founder grant decides, once and permanently, whether a user gets Pro
//  free forever. Every branch below is a silent-wrong-answer bug if it flips:
//  granting too widely costs the revenue, granting too narrowly breaks the
//  promise in docs/monetization-strategy.md §7 to the users who were here first.
//

import Foundation
import StoreKit
import Testing
@testable import GymStreak

@Suite
@MainActor
struct FounderStatusTests {

    // MARK: - Granting

    @Test("A verified production download from before the cutoff grants Founder")
    func preCutoffGrants() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Every pre-monetization release shipped as build "1".
        let service = makeService(.production, originalAppVersion: "1", defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder)
        #expect(service.isDecided)
    }

    @Test("The cutoff build itself does not grant — the comparison is strictly less-than")
    func cutoffBuildDoesNotGrant() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = makeService(
            .production,
            originalAppVersion: String(FounderStatusService.cutoffBuild),
            defaults: defaults
        )

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        // Decided, not undecided: this user genuinely is not a Founder, so the
        // answer is cached and never re-asked.
        #expect(service.isDecided)
    }

    @Test("A download after the cutoff does not grant")
    func postCutoffDoesNotGrant() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = makeService(.production, originalAppVersion: "1001", defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        #expect(service.isDecided)
    }

    // MARK: - The four traps (§7.1)

    @Test(
        "Non-production environments never grant, and stay undecided",
        arguments: [AppStore.Environment.sandbox, .xcode]
    )
    func nonProductionNeverGrants(_ environment: AppStore.Environment) async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Sandbox, TestFlight and Xcode all report "1.0", which parses to no
        // Int and would otherwise look pre-cutoff to a string comparison.
        let service = makeService(environment, originalAppVersion: "1.0", defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        // Undecided on purpose: a TestFlight run must not burn in an answer that
        // the same user's later App Store install would inherit.
        #expect(service.isDecided == false)
    }

    @Test("An unverified transaction never grants — this is the forgery vector")
    func unverifiedNeverGrants() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FounderStatusService(
            downloads: StubDownloadReader(.download(.unverified)),
            defaults: defaults
        )

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        #expect(service.isDecided == false)
    }

    @Test("A non-numeric original version never grants")
    func nonNumericVersionDoesNotGrant() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Guards the trap directly: as a string, "1.0" sorts before "1000", so a
        // lexicographic or `.numeric` comparison would grant here.
        let service = makeService(.production, originalAppVersion: "1.0", defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        #expect(service.isDecided == false)
    }

    @Test("A thrown lookup leaves the decision undecided and persists nothing")
    func throwLeavesUndecided() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reader = StubDownloadReader(.failure)
        let service = FounderStatusService(downloads: reader, defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        #expect(service.isDecided == false)
        // Nothing at all was written — a persisted `false` would disinherit a
        // Founder whose first launch merely happened to be offline.
        #expect(defaults.object(forKey: "pro.isFounder") == nil)
    }

    @Test("A launch that failed to resolve is retried, and can still grant")
    func failedResolutionIsRetriedNextLaunch() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reader = StubDownloadReader(.failure)
        let service = FounderStatusService(downloads: reader, defaults: defaults)
        await service.resolveIfNeeded()

        // Next launch: back online.
        reader.outcome = .download(.verified(environment: .production, originalAppVersion: "1"))
        await service.resolveIfNeeded()

        #expect(service.isFounder)
        #expect(reader.callCount == 2)
    }

    // MARK: - Resolving at most once

    @Test("A settled decision is never re-asked")
    func decisionResolvesAtMostOnce() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reader = StubDownloadReader(
            .download(.verified(environment: .production, originalAppVersion: "1"))
        )
        let service = FounderStatusService(downloads: reader, defaults: defaults)

        await service.resolveIfNeeded()
        await service.resolveIfNeeded()
        await service.resolveIfNeeded()

        #expect(reader.callCount == 1)
        #expect(service.isFounder)
    }

    @Test("The cached decision survives into a new service instance")
    func decisionSurvivesRelaunch() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = makeService(.production, originalAppVersion: "1", defaults: defaults)
        await first.resolveIfNeeded()

        // A fresh launch: new instance, same defaults, and a reader that would
        // now report a post-cutoff download.
        let relaunchReader = StubDownloadReader(
            .download(.verified(environment: .production, originalAppVersion: "1001"))
        )
        let second = FounderStatusService(downloads: relaunchReader, defaults: defaults)
        await second.resolveIfNeeded()

        #expect(second.isFounder)
        #expect(relaunchReader.callCount == 0)
    }

    // MARK: - The cutoff itself

    @Test("The cutoff is the documented build number")
    func cutoffValue() {
        #expect(FounderStatusService.cutoffBuild == 1000)
    }

    /// The load-bearing invariant from `docs/monetization-strategy.md` §7.1:
    /// this suite is hosted by the real app, so it reads the app's actual
    /// shipping build number. If a release ever regresses below the cutoff,
    /// every new paying user is silently granted Pro forever — and the only
    /// other symptom is missing revenue, months later. Fail here instead.
    @Test("The app's own build number is not below the cutoff")
    func shippingBuildIsNotBelowCutoff() throws {
        let rawBuild = try #require(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
        let build = try #require(Int(rawBuild), "CFBundleVersion must be a plain integer")

        #expect(build >= FounderStatusService.cutoffBuild)
    }

    // MARK: - The debug simulator (§9.4c)

    /// The simulated reader exists so the grant can be walked on a device at
    /// all — outside a production App Store install the real one can never
    /// grant (§7.1 trap 2). These pin that it simulates the *right* two cases:
    /// a simulator that quietly stopped granting, or that granted at the
    /// cutoff, would send a device pass to the wrong conclusion about shipping
    /// code, which is worse than having no simulator.

    @Test("The pre-cutoff argument simulates a download that grants Founder")
    func simulatedPreCutoffGrants() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reader = try #require(
            SimulatedOriginalAppDownloadReader.fromLaunchArguments(
                [SimulatedOriginalAppDownloadReader.preCutoffArgument]
            )
        )
        let service = FounderStatusService(downloads: reader, defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder)
    }

    /// Follows `cutoffBuild` rather than hard-coding `1000`, so re-pinning the
    /// cutoff cannot silently turn the simulator's negative case into a grant.
    @Test("The cutoff argument simulates the boundary, which does not grant")
    func simulatedCutoffDoesNotGrant() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let reader = try #require(
            SimulatedOriginalAppDownloadReader.fromLaunchArguments(
                [SimulatedOriginalAppDownloadReader.cutoffArgument]
            )
        )
        let service = FounderStatusService(downloads: reader, defaults: defaults)

        await service.resolveIfNeeded()

        #expect(service.isFounder == false)
        #expect(service.isDecided)
    }

    @Test("Without an argument there is no simulator, so the real reader is used")
    func noArgumentMeansNoSimulator() {
        #expect(SimulatedOriginalAppDownloadReader.fromLaunchArguments([]) == nil)
        #expect(SimulatedOriginalAppDownloadReader.fromLaunchArguments(["-PRO_GATING_OFF"]) == nil)
    }

    /// The safety property the whole simulator rests on: a simulated run must
    /// never write the real `pro.isFounder`, because that decision is recorded
    /// once and kept forever — a leak would mark the device Founder permanently,
    /// with no gate in sight and nothing on screen to say why.
    ///
    /// `UserDefaults(suiteName:)` returns `nil` only for a nonsensical name
    /// (`NSGlobalDomain`, a CFPreferences constant, or the app's own bundle id),
    /// and `AppDependencies` falls back to *not simulating* if it ever does.
    /// This asserts the fallback stays unreachable, which is the difference
    /// between the separation being structural and being aspirational.
    @Test("The simulated suite name is usable, so the real defaults are never the fallback")
    func simulatedSuiteNameIsUsable() throws {
        let suiteName = SimulatedOriginalAppDownloadReader.defaultsSuiteName
        #expect(suiteName != Bundle.main.bundleIdentifier)
        #expect(suiteName != UserDefaults.globalDomain)

        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        // And that it really is a separate store: a value written through the
        // suite must not appear in `.standard` under the same key.
        let probeKey = "FounderStatusTests.suiteIsolation"
        suite.set(true, forKey: probeKey)
        #expect(UserDefaults.standard.object(forKey: probeKey) == nil)
    }

    // MARK: - Helpers

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "FounderStatusTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeService(
        _ environment: AppStore.Environment,
        originalAppVersion: String,
        defaults: UserDefaults
    ) -> FounderStatusService {
        FounderStatusService(
            downloads: StubDownloadReader(
                .download(
                    .verified(environment: environment, originalAppVersion: originalAppVersion)
                )
            ),
            defaults: defaults
        )
    }
}

// MARK: - Doubles

/// Stands in for StoreKit, which offers no way to build an `AppTransaction`:
/// the type has no public initializer, so the seam is the only way to reach
/// these branches from a unit test.
@MainActor
private final class StubDownloadReader: OriginalAppDownloadReading {

    enum Outcome {
        case download(OriginalAppDownload)
        /// Offline, or not signed in to the App Store.
        case failure
    }

    var outcome: Outcome
    private(set) var callCount = 0

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func originalAppDownload() async throws -> OriginalAppDownload {
        callCount += 1
        switch outcome {
        case .download(let download): return download
        case .failure: throw StubLookupError()
        }
    }
}

private struct StubLookupError: Error {}
