//
//  ReviewPromptHost.swift
//  GymStreak
//
//  The one place `requestReview` is invoked. See docs/rating-prompt.md.
//

import StoreKit
import SwiftUI

/// Invokes the system's App Store review request when
/// `ReviewPromptCoordinator` says one is due.
///
/// It carries no decision — every rule about *whether* to ask lives in the
/// coordinator (Hard rule 3). What lives here is the one thing a view has and a
/// coordinator does not: `@Environment(\.requestReview)`, which is only
/// meaningfully populated inside the SwiftUI environment graph.
///
/// **Attach it to the app root, never inside a sheet or a pushed screen.** The
/// action is tied to the scene of the view that reads it, and a call made from a
/// transient presentation context can be dropped with no error and no feedback
/// (Apple Developer Forums 739656) — which, for a once-ever ask, would spend the
/// only chance on an alert nobody saw.
private struct ReviewPromptHost: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    let coordinator: ReviewPromptCoordinator

    func body(content: Content) -> some View {
        content.onChange(of: coordinator.isRequestDue) { _, isDue in
            guard isDue else { return }
            Task { @MainActor in
                // Apple's own sample for this API delays the call so it does not
                // land on top of what the person was doing, and this app needs
                // the delay for a second reason: the ask is decided while the
                // save sheet — and, under it, the active-workout cover — are
                // still unwinding, and an alert requested mid-dismissal is
                // exactly the case that gets silently dropped. Both animations
                // are long finished by the time this fires.
                try? await Task.sleep(for: .seconds(Self.settleDelaySeconds))
                // Re-checked after the wait, so the ask and the record it spends
                // can never come apart: the coordinator refuses a report that no
                // longer matches a due request, and this makes the call obey the
                // same refusal.
                guard coordinator.isRequestDue else { return }
                // Recorded immediately before the call rather than after it:
                // `requestReview()` returns `Void` and reports nothing about
                // whether an alert appeared, so "we asked" is the only fact
                // there is, and it has to be written on the same turn as the ask
                // to stay one-way.
                coordinator.reviewWasRequested()
                requestReview()
            }
        }
    }

    /// Two seconds, the value in Apple's own sample code for this API.
    private static let settleDelaySeconds = 2.0
}

extension View {
    /// Lets the app root ask for an App Store rating when one is due.
    ///
    /// Exactly one call site, at the root: see `ReviewPromptHost`.
    func reviewPromptHost(_ coordinator: ReviewPromptCoordinator) -> some View {
        modifier(ReviewPromptHost(coordinator: coordinator))
    }
}
