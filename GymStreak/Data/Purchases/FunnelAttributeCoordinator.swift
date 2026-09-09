//
//  FunnelAttributeCoordinator.swift
//  GymStreak
//
//  Gathers the four anonymous funnel facts and hands them to the purchase
//  backend's attribute surface. See docs/funnel-instrumentation.md.
//

import Foundation
import OSLog
import StoreKit

/// Reads where this install stands — tour finished, workouts logged, routines
/// built, how it was installed — and reports the buckets onwards.
///
/// **It exists so the gateway does not have to.** `RevenueCatPurchaseGateway`
/// answers none of these questions and must never grow a `ModelContext` or a
/// repository to do so; that would put persistence knowledge into the purchase
/// layer. So the gathering lives here, the gateway only writes what it is
/// handed, and the three sites that know a user moved
/// (`OnboardingFlowViewModel`, `RoutinesViewModel`, `WorkoutViewModel`) call one
/// `FunnelAttributeTracking` method without knowing either half.
///
/// App-lifetime, held by `AppDependencies`, because the build channel is
/// resolved at most once per process and a second instance would ask StoreKit
/// again.
@MainActor
final class FunnelAttributeCoordinator: FunnelAttributeTracking {

    private let onboarding: any OnboardingCompletionTracking
    private let totals: any LifetimeTrainingTotalsProviding
    private let routineRepository: RoutineRepository
    private let downloads: any OriginalAppDownloadReading
    private let reporter: any FunnelAttributeReporting

    /// The resolved channel, memoized as the `Task` that resolves it so two
    /// overlapping reports share one StoreKit read rather than racing to make
    /// two. Started lazily on the first report, never in `init` — nothing about
    /// composing the app may reach for StoreKit.
    ///
    /// The task yields `nil` for "could not ask", and that answer is **not**
    /// kept: a first launch that was offline would otherwise pin an App Store
    /// user to `"other"` for the whole session.
    private var buildChannelResolution: Task<AppBuildChannel?, Never>?

    init(
        onboarding: any OnboardingCompletionTracking,
        totals: any LifetimeTrainingTotalsProviding,
        routineRepository: RoutineRepository,
        downloads: any OriginalAppDownloadReading,
        reporter: any FunnelAttributeReporting
    ) {
        self.onboarding = onboarding
        self.totals = totals
        self.routineRepository = routineRepository
        self.downloads = downloads
        self.reporter = reporter
    }

    /// Reads the four facts and reports them.
    ///
    /// The count comes from `fetchCompletedWorkoutCount()` — the counting query,
    /// not `fetchLifetimeTotals()`, whose whole-history walk shares the History
    /// model actor and would queue behind (and in front of) the History tab's
    /// own refetch. **No counter of its own, no `@AppStorage` tally**: a second
    /// count is a second thing that can disagree with the History screen.
    ///
    /// A count that throws reports nothing at all rather than reporting `"0"`.
    /// The two are indistinguishable in the dashboard and "nobody trains"
    /// is precisely the conclusion this lever exists to test — writing it from
    /// a failed read would manufacture the answer. The next event re-reports.
    func reportCurrentState() async {
        let completedWorkoutCount: Int
        do {
            completedWorkoutCount = try await totals.fetchCompletedWorkoutCount()
        } catch {
            Self.logger.info(
                "Funnel report skipped — workout count unavailable: \(String(describing: error), privacy: .public)"
            )
            return
        }

        reporter.report(
            FunnelAttributes.make(
                hasCompletedOnboarding: onboarding.hasCompletedOnboarding,
                completedWorkoutCount: completedWorkoutCount,
                // The one counting rule the cap already uses, and the reason
                // this attribute is not a plain `fetchAll().count`: the app
                // seeds a starter routine, so a raw count reports `1` for a user
                // who built nothing — the exact opposite of the question
                // "does the starter routine carry them?" (docs/example-starter-routine.md).
                userCreatedRoutineCount: RoutineCapPolicy.countableRoutineCount(
                    in: routineRepository.fetchAll()
                ),
                buildChannel: await buildChannel()
            )
        )
    }

    /// `.appStore` only for a *verified* `AppTransaction` in the `.production`
    /// environment. TestFlight and a device build against a Sandbox account both
    /// report `.sandbox`, a StoreKit-configuration run reports `.xcode`, and an
    /// unverified result, a throw or no answer at all report nothing — every one
    /// of those is `.other`, because the attribute exists to *exclude* noise and
    /// must fail toward the exclusion.
    ///
    /// **Resolved once per process, and deliberately not persisted.** The
    /// environment is stable for a given install, but an install is not: a
    /// TestFlight tester who later takes the App Store build keeps the same
    /// container, and a cached `"other"` would misreport them forever — which is
    /// the §1.1 contamination this lever is here to end, only quieter.
    ///
    /// `AppTransaction.shared` is documented to *throw* — not block — when the
    /// user is unauthenticated or offline, and StoreKit keeps a local copy that
    /// it refreshes itself, so this needs no network call of its own after the
    /// first. It is nevertheless never on a path anything waits on:
    /// `AppTransaction.refresh()` and every purchase API stay out of this path,
    /// so there is no route from here to a sign-in sheet.
    private func buildChannel() async -> AppBuildChannel {
        if let resolved = await buildChannelResolution?.value {
            return resolved
        }
        let resolution = Task { [downloads] () -> AppBuildChannel? in
            do {
                guard case .verified(let environment, _) = try await downloads.originalAppDownload() else {
                    // The signature did not check out. Not App Store *proven*,
                    // so not App Store — the same fail-closed reading
                    // `FounderStatusService` takes of an unverified result.
                    return .other
                }
                return environment == .production ? .appStore : .other
            } catch {
                return nil
            }
        }
        buildChannelResolution = resolution
        guard let resolved = await resolution.value else {
            // Nothing learned, so nothing is remembered — the next report asks
            // again — and this one reports the fail-toward value. Cleared only
            // if this is still *our* task, so a concurrent report that has
            // already started a fresh one is not thrown away.
            if buildChannelResolution == resolution {
                buildChannelResolution = nil
            }
            return .other
        }
        return resolved
    }

    private static let logger = Logger(subsystem: "app.gymstreak.pro", category: "Funnel")
}
