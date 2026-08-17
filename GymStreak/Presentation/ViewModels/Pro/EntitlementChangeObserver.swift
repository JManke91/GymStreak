//
//  EntitlementChangeObserver.swift
//  GymStreak
//
//  Bridges the `@Observable` entitlement provider to the legacy
//  `ObservableObject` ViewModels. See docs/pro-subscription.md §3c.
//

import Foundation
import Observation

/// Calls back whenever the Pro entitlement changes.
///
/// **Why this exists.** Every gate computes its answer live from
/// `ProEntitlementProviding`, so after a purchase the *value* is already
/// correct — but a `class … : ObservableObject` ViewModel that reads it emits no
/// `objectWillChange`, and SwiftUI has no reason to re-render. The lock stayed
/// on screen until the app was relaunched, with the underlying property
/// reporting Pro the whole time. `@Observable` ViewModels and views that read
/// `state` inside `body` need none of this: their reads are tracked
/// transitively.
///
/// It observes `state` rather than `isPro` deliberately. `isPro` collapses four
/// entitlements into a `Bool`, so a subscription upgrading to lifetime — or a
/// Founder grant resolving over a purchase — would notify nothing, and the
/// Settings section (§5i) names the source, not just the tier.
///
/// `withObservationTracking` is **one-shot**: it reports the first change to the
/// properties read in its `apply` block and then stops. Re-arming inside the
/// callback is what makes it a subscription rather than a single notification —
/// forgetting that is the classic way this pattern half-works, updating once and
/// never again.
@MainActor
final class EntitlementChangeObserver {

    private let entitlements: any ProEntitlementProviding
    private let onChange: @MainActor () -> Void

    /// Starts observing immediately — an observer that has to be started is one
    /// a future ViewModel will forget to start.
    init(
        entitlements: any ProEntitlementProviding,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.entitlements = entitlements
        self.onChange = onChange
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = entitlements.state
        } onChange: { [weak self] in
            // `onChange` is `nonisolated` and runs *during* the mutation, before
            // the new value is stored, so the hop is not optional: it is what
            // makes the callback see the value that was just written. `Task`
            // rather than `DispatchQueue.main.async` per the concurrency rules —
            // SE-0431 ordering is what keeps a burst of changes in sequence.
            Task { @MainActor in
                guard let self else { return }
                self.onChange()
                self.observe()
            }
        }
    }
}
