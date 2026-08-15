//
//  FounderStatusService.swift
//  GymStreak
//
//  Decides once, permanently and offline-durably, whether this install
//  predates monetization and therefore gets Pro free forever.
//  See docs/pro-subscription.md and docs/monetization-strategy.md §7/§7.1.
//

import Foundation
import StoreKit

/// The App Store's signed record of the original app download, reduced to the
/// two facts the Founder decision needs.
///
/// This exists because `AppTransaction` has **no public initializer** — verified
/// against Apple's documentation on 2026-08-15: every value-producing path
/// (`shared`, `refresh()`) routes through StoreKit's real signing pipeline, so a
/// `VerificationResult<AppTransaction>` cannot be built in a unit test at all.
/// Without this projection the six branches of the decision below — the ones
/// that each silently grant or withhold a permanent entitlement — would be
/// untestable.
enum OriginalAppDownload: Equatable, Sendable {

    /// StoreKit verified the signature. Carries only what the decision reads.
    case verified(environment: AppStore.Environment, originalAppVersion: String)

    /// The signature check failed. Never grants — see `FounderStatusService`.
    case unverified
}

/// Reads the App Store's record of the original app download.
///
/// `@MainActor` rather than `Sendable`-and-isolation-agnostic: `AppTransaction`
/// declares no main-actor requirement and both it and `VerificationResult` are
/// `Sendable` (verified 2026-08-15), so the caller may await it directly from
/// the main actor — Concurrency rule 5's "no escape hatch needed" case. The work
/// is a suspending I/O round-trip, not main-thread computation.
@MainActor
protocol OriginalAppDownloadReading {
    func originalAppDownload() async throws -> OriginalAppDownload
}

/// Production reader: StoreKit 2's `AppTransaction`.
///
/// Chosen over every local signal (SwiftData `createdAt`, documents-directory
/// creation date, an iCloud KVS stamp) because it is the only one that survives
/// the case that decides the whole grant: *the user deleted the app before the
/// paywall existed and reinstalled after it*. See §7.1's survivability table.
///
/// Stateless; its isolation is inferred from the `@MainActor` protocol it
/// conforms to, so the composition root constructs it explicitly rather than it
/// appearing as a default argument (a default argument expression is evaluated
/// outside the enclosing declaration's isolation).
struct StoreKitOriginalAppDownloadReader: OriginalAppDownloadReading {

    func originalAppDownload() async throws -> OriginalAppDownload {
        switch try await AppTransaction.shared {
        case .verified(let transaction):
            .verified(
                environment: transaction.environment,
                originalAppVersion: transaction.originalAppVersion
            )
        case .unverified:
            .unverified
        }
    }
}

/// Whether this install predates the monetization cutoff build.
@MainActor
protocol FounderStatusResolving: AnyObject {

    /// `true` only once the decision has resolved *in the user's favour*.
    /// Undecided reports `false` — nothing is granted on a guess.
    var isFounder: Bool { get }

    /// Resolves the decision unless it is already settled. A cheap no-op on
    /// every launch after the first successful resolution.
    func resolveIfNeeded() async
}

/// Grants Founder to every install whose original download predates
/// `cutoffBuild`, deciding at most once and caching the answer forever.
///
/// **The cutoff is a build number, not a marketing version.** On iOS
/// `originalAppVersion` returns `CFBundleVersion`; macOS returns
/// `CFBundleShortVersionString` and a macOS sample copied here would compare the
/// wrong string (§7.1 trap 1).
@MainActor
final class FounderStatusService: FounderStatusResolving {

    /// Installs reporting an original build **below** this are Founders.
    ///
    /// Every pre-monetization release shipped as build `1`: this project never
    /// incremented `CURRENT_PROJECT_VERSION`, so all of App Store Connect reads
    /// `1.1.x (1)`. The monetization release is the first to carry `1000`, which
    /// is what makes `1 < 1000` a correct and complete test for "was here
    /// before the paywall".
    ///
    /// **Load-bearing invariant: no future release may ship a build number below
    /// this.** If one does, every new paying user is silently granted Pro
    /// forever and the only symptom is missing revenue. The `/release` and
    /// `merge-testflight-to-store` commands increment the build each cycle to
    /// hold this — see their Founder-grant warnings.
    static let cutoffBuild = 1000

    /// Absent = undecided. Deliberately three-valued (`nil` / `true` / `false`)
    /// rather than a `Bool`: a genuine first-launch-offline must be retried, and
    /// `UserDefaults.bool(forKey:)` cannot tell "not resolved yet" from "resolved
    /// to not-a-Founder".
    private static let decisionKey = "pro.isFounder"

    private let downloads: any OriginalAppDownloadReading
    private let defaults: UserDefaults

    init(
        downloads: any OriginalAppDownloadReading,
        defaults: UserDefaults = .standard
    ) {
        self.downloads = downloads
        self.defaults = defaults
    }

    var isFounder: Bool { defaults.bool(forKey: Self.decisionKey) }

    /// `true` once a resolution has been recorded, either way.
    var isDecided: Bool { defaults.object(forKey: Self.decisionKey) != nil }

    func resolveIfNeeded() async {
        guard !isDecided else { return }
        guard let decision = await resolveDecision() else { return }
        defaults.set(decision, forKey: Self.decisionKey)
    }

    /// The decision, or `nil` for "cannot decide — ask again next launch".
    ///
    /// Every `nil` below is a deliberate fail-closed: it neither grants nor
    /// records a negative, so a later launch in better conditions can still
    /// grant. Recording `false` here would permanently disinherit a Founder.
    private func resolveDecision() async -> Bool? {
        let download: OriginalAppDownload
        do {
            download = try await downloads.originalAppDownload()
        } catch {
            // Offline or not signed in on a true first launch (§7.1 trap 4).
            return nil
        }

        // `.unverified` is precisely the forge-a-pre-cutoff-transaction vector.
        guard case .verified(let environment, let originalAppVersion) = download else {
            return nil
        }
        // Sandbox, TestFlight and Xcode always report "1.0", so every non-production
        // run would otherwise look pre-cutoff (§7.1 trap 2). Guarding on the
        // environment rather than special-casing that string is what keeps a
        // TestFlight tester from being granted Founder.
        guard environment == .production else { return nil }
        // Parsed as `Int`, never compared as a string: `.compare(_:options:.numeric)`
        // falls back to lexicographic ordering on a non-numeric component and
        // returns a wrong answer without erroring (§7.1 trap 3).
        guard let originalBuild = Int(originalAppVersion) else { return nil }

        return originalBuild < Self.cutoffBuild
    }
}
