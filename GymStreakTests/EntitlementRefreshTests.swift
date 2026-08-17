//
//  EntitlementRefreshTests.swift
//  GymStreakTests
//
//  That a purchase or a restore repaints the gates *without an app restart*.
//  See docs/pro-subscription.md §3c.
//
//  These assert on **change notification**, not on the value. Every gate in the
//  app already computes its answer live from `ProEntitlementProviding`, so a
//  test that only read the property back would have passed while the shipped app
//  kept showing a lock until relaunch — which is exactly the bug this file
//  exists for. What was missing was anything telling SwiftUI to re-render.
//

import Combine
import Foundation
import Observation
import SwiftData
import Testing
@testable import GymStreak

@Suite
@MainActor
struct EntitlementRefreshTests {

    // MARK: - P1, the reported symptom

    @Test("Buying Pro repaints the routines list without a relaunch")
    func routinesRepublishOnPurchase() async {
        let harness = makeRoutines()

        let emissions = await harness.viewModel.emissionCount {
            harness.entitlements.state = .subscription
        }

        #expect(emissions > 0)
        #expect(harness.viewModel.isRoutineCapReached == false)
    }

    @Test("A lapse repaints it too")
    func routinesRepublishOnLapse() async {
        let harness = makeRoutines(state: .subscription)

        let emissions = await harness.viewModel.emissionCount {
            harness.entitlements.state = .free
        }

        #expect(emissions > 0)
    }

    /// The §8 D nudge is the other half of the same screen, and it has its own
    /// three-state rule — "one left", "at the cap", nothing.
    @Test("The cap nudge disappears the moment the purchase lands")
    func capNudgeClearsOnPurchase() async {
        let harness = makeRoutines()
        harness.fillToCap()

        #expect(harness.viewModel.routineCapNudge != nil)

        let emissions = await harness.viewModel.emissionCount {
            harness.entitlements.state = .lifetime
        }

        #expect(emissions > 0)
        #expect(harness.viewModel.routineCapNudge == nil)
    }

    // MARK: - P2

    @Test("Buying Pro unblurs the progress chart without a relaunch")
    func chartRepublishesOnPurchase() async {
        let entitlements = ObservableStubEntitlements(state: .free)
        let viewModel = ExerciseProgressViewModel(
            exerciseName: "Bench Press",
            provider: SilentHistorySnapshotProvider(),
            proEntitlements: entitlements,
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: true
        )

        let emissions = await viewModel.emissionCount {
            entitlements.state = .subscription
        }

        #expect(emissions > 0)
    }

    // MARK: - A restore is the same event

    /// Restore reaches the app by the same path a purchase does — the provider's
    /// state changing — so the guarantee has to hold for a state that arrives
    /// without the user having tapped Buy in this session.
    @Test("A restore repaints the gates like a purchase does")
    func restoreRepublishes() async {
        let harness = makeRoutines()

        let emissions = await harness.viewModel.emissionCount {
            // What `restorePurchases()` ends up doing: recompose to `.lifetime`.
            harness.entitlements.state = .lifetime
        }

        #expect(emissions > 0)
        #expect(harness.viewModel.isRoutineCapReached == false)
    }

    // MARK: - P3, P4, P5 — the metered AI surfaces

    /// The AI ViewModels are `@Observable`, so they need no republisher — but
    /// only if the entitlement read is *live*. `AICoachAllowanceGate` is the
    /// object all three read through, and it is a plain class, so this pins the
    /// chain SwiftUI actually depends on: touching `nudgeState` must register a
    /// dependency on the provider, not hand back a cached answer.
    ///
    /// Written with `withObservationTracking` rather than `objectWillChange`
    /// because that *is* the mechanism SwiftUI uses to decide whether to
    /// re-render a view reading this.
    @Test("An AI taster surface tracks the entitlement rather than caching it")
    func aiAllowanceGateIsTracked() async {
        let entitlements = ObservableStubEntitlements(state: .free)
        let gate = AICoachAllowanceGate(
            surface: .periodRecap,
            entitlements: entitlements,
            paywalls: RecordingPaywallPresenter(),
            allowance: MonthlyAllowanceStore(
                defaults: UserDefaults(
                    suiteName: "EntitlementRefreshTests.\(UUID().uuidString)"
                )!,
                cloud: NoopAllowanceCloudStore(),
                calendar: .current,
                now: { Date() }
            ),
            availability: StubAICoachAvailability(state: .available),
            isGatingEnabled: true
        )

        // `onChange` is `nonisolated`, so the flag has to be somewhere both
        // isolations can reach — the same shape the real observer uses.
        let didInvalidate = InvalidationFlag()
        withObservationTracking {
            _ = gate.nudgeState
        } onChange: {
            didInvalidate.set()
        }

        entitlements.state = .subscription
        for _ in 0..<10 { await Task.yield() }

        #expect(didInvalidate.wasSet)
    }

    // MARK: - P4 — the one surface that stores its gate

    /// The recap is the exception to the row above: `.gated` is written into
    /// `state`, not derived, so a purchase left the lock on screen **and killed
    /// its own CTA** — `unlock()` asks the presenter, which refuses a paywall to
    /// a Pro user, so the button did nothing at all. Worse than the bug this
    /// change set out to fix, and on a screen the first audit cleared.
    ///
    /// The contract is the view's re-entry key: it must change when the user
    /// stops being metered, because that is what re-runs `.task(id:)` and lets
    /// the recap the user just paid for actually generate.
    @Test("Buying Pro clears the recap's stored gate instead of stranding it")
    func recapGateIsNotStrandedByAPurchase() async throws {
        let entitlements = ObservableStubEntitlements(state: .free)
        let harness = PeriodRecapHarness(entitlements: entitlements)
        harness.seedSessions(count: 5)
        harness.exhaustAllowance()

        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()
        guard case .gated = harness.viewModel.state else {
            Issue.record("expected .gated, got \(harness.viewModel.state)")
            return
        }
        let keyWhileGated = harness.viewModel.allowanceReloadKey

        entitlements.state = .subscription
        for _ in 0..<10 { await Task.yield() }

        #expect(harness.viewModel.allowanceReloadKey != keyWhileGated)

        // …and re-entering on that key leaves the dead end.
        await harness.viewModel.load(modelContext: harness.context)
        await harness.viewModel.waitForCurrentGeneration()
        if case .gated = harness.viewModel.state {
            Issue.record("still gated after buying Pro")
        }
    }

    // MARK: - It must not fire on unrelated churn

    /// A republish per unrelated change would re-render the routines list on
    /// every entitlement read, which is the failure mode that makes people
    /// distrust observation. Setting the same value must not notify.
    ///
    /// Asserted against the observer rather than a ViewModel on purpose: a
    /// ViewModel emits `objectWillChange` for many reasons of its own (a
    /// `@Published` write, a CloudKit notification, watch availability), so
    /// counting *its* emissions would measure ambient churn and go red for
    /// reasons that have nothing to do with the entitlement.
    ///
    /// The guarantee comes from Observation, not from this code: the `@Observable`
    /// macro compares before notifying when the property is `Equatable`, and
    /// `ProEntitlementState` is a raw-value enum. **Do not delete this on the
    /// belief that the macro notifies unconditionally** — that reading came up in
    /// the §3d review and this test is what disproves it.
    ///
    /// `ProEntitlementProvider.recompose()` no longer depends on it either way
    /// (§3d gave it its own equality guard), which matters because `refresh()`
    /// recomposes three times per call and has three callers.
    @Test("Re-reporting the same entitlement notifies nothing")
    func idempotentStateDoesNotNotify() async {
        let entitlements = ObservableStubEntitlements(state: .subscription)
        var callbacks = 0
        let observer = EntitlementChangeObserver(entitlements: entitlements) {
            callbacks += 1
        }

        entitlements.state = .subscription
        for _ in 0..<10 { await Task.yield() }
        #expect(callbacks == 0)

        // …and a real change still gets through, so this is not passing because
        // the observer is inert.
        entitlements.state = .free
        for _ in 0..<10 { await Task.yield() }
        #expect(callbacks == 1)

        // Explicit rather than a bare `_ = observer`: nothing else references it,
        // and a reader tidying that line away would silently delete the test.
        withExtendedLifetime(observer) {}
    }

    // MARK: - Helpers

    /// Gating **on**, unlike the shipped app: with the real `ProGating.isEnabled`
    /// every one of these would pass by proving the gate is inert.
    private func makeRoutines(state: ProEntitlementState = .free) -> RoutinesHarness {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let entitlements = ObservableStubEntitlements(state: state)
        let viewModel = RoutinesViewModel(
            routineRepository: SwiftDataRoutineRepository(modelContext: context),
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            watchSync: MockWatchSyncServicing(),
            proEntitlements: entitlements,
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: true
        )
        return RoutinesHarness(viewModel: viewModel, entitlements: entitlements)
    }
}
