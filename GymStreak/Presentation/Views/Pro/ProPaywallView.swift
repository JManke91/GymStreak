//
//  ProPaywallView.swift
//  GymStreak
//
//  What a raised placement actually looks like: the RevenueCat paywall the
//  dashboard authored for that placement. See docs/pro-subscription.md §5j.
//

import SwiftUI
import OSLog
import RevenueCat
import RevenueCatUI

/// Resolves a `PaywallPlacement` to a dashboard offering and renders its paywall.
///
/// This is one of the two files above `Data/Purchases/` allowed to import
/// RevenueCat — the other is `CustomerCenterSettingsRow` — and the reason is
/// narrow: `PaywallView(offering:)` takes an `Offering`, so
/// the type has to be nameable here. Nothing else leaks — the presenter, the
/// placement enum and all nine gates stay SDK-free, which is what let ticket 04
/// ship a placeholder in this exact position and ticket 14 swap it without a
/// caller changing.
///
/// **It decides nothing about eligibility.** The kill switch, Rule 3 (no paywall
/// inside an active workout), the entitlement — a Founder included — and §8's
/// once-ever cap are all settled in `PaywallPresenter` before this view is ever
/// constructed. A view that could be reached without them would be a way around
/// them.
struct ProPaywallView: View {

    let placement: PaywallPlacement

    /// The app's single source of truth on entitlement. Injected rather than
    /// asked of the SDK here: a restore has to be judged by the same rule every
    /// gate is judged by, including the fail-closed treatment of an
    /// unverifiable response (§3b), and that rule lives in one place.
    let entitlements: any ProEntitlementProviding

    /// The endowed-progress figures for `.valueMoment` (§8 B), ignored by every
    /// other placement. A dashboard-authored paywall cannot know the user's own
    /// numbers, so they are rendered by the app, above the paywall — see §5j.
    var lifetimeTotals: LifetimeTrainingTotals?

    /// Reported once a real paywall is on screen.
    ///
    /// Not `onAppear`: this view appears in its loading state, and a placement
    /// whose offering never resolves must not spend §8's once-ever fire on a
    /// sheet that showed no offer. So it fires from the resolution, on the two
    /// rungs that produce a paywall, and never on `.unavailable`.
    var onPaywallShown: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case ready(Offering)
        case unavailable
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            switch phase {
            case .loading:
                ProgressView()
                    .tint(DesignSystem.Colors.tint)

            case .ready(let offering):
                VStack(spacing: 0) {
                    if let figures = valueMomentFigures {
                        valueMomentHeader(figures)
                    }

                    PaywallView(offering: offering, displayCloseButton: true)
                        // The close button, and anything else the paywall itself
                        // decides should close it.
                        .onRequestedDismissal { dismiss() }
                        // A completed purchase dismisses the paywall **here**,
                        // explicitly. RevenueCat does not auto-dismiss on a
                        // successful purchase and does not route one through
                        // `onRequestedDismissal` (purchases-ios #3617, #3691) —
                        // assuming it did left the user staring at the paywall
                        // they had just paid on.
                        //
                        // The `refresh()` is belt and braces on top of
                        // `customerInfoStream`: the stream is what normally
                        // flips the entitlement, but it is delivery we do not
                        // control, and this is the one moment where a late
                        // update is most visible. It re-reads RevenueCat's cache
                        // — which the purchase has itself just refreshed — and
                        // since §3d a read that fails changes nothing, so it
                        // cannot degrade what the purchase just granted.
                        .onPurchaseCompleted { _ in
                            dismiss()
                            Task { await entitlements.refresh() }
                        }
                        // Restore has no such hook, and a restore that found
                        // nothing must leave the paywall up rather than read as
                        // success — hence the explicit check. The handed-in
                        // `CustomerInfo` is deliberately ignored: judging it
                        // here would be a second answer to "is this user Pro",
                        // and a laxer one than the gateway's, which refuses an
                        // entitlement whose response failed verification (§3b).
                        .onRestoreCompleted { _ in
                            Task {
                                await entitlements.refresh()
                                if entitlements.isPro { dismiss() }
                            }
                        }
                }

            case .unavailable:
                unavailableView
            }
        }
        .task { await resolveOffering() }
    }

    // MARK: - Resolution

    /// Placement offering → default offering → nothing, per `PaywallOfferingSource`.
    private func resolveOffering() async {
        // A paywall can only be built against a configured SDK. In the app that
        // is guaranteed (the composition root configures in `init`), so this
        // guard is for previews and for a hypothetical configuration failure —
        // `Purchases.shared` traps rather than returning nil.
        guard Purchases.isConfigured else {
            phase = .unavailable
            return
        }

        let offerings = try? await Purchases.shared.offerings()
        let placementOffering = offerings?.currentOffering(forPlacement: placement.identifier)
        let defaultOffering = offerings?.current
        let source = PaywallOfferingSource.resolve(
            hasPlacementOffering: placementOffering != nil,
            hasDefaultOffering: defaultOffering != nil
        )

        guard let offering = placementOffering ?? defaultOffering else {
            Self.logger.info(
                """
                Paywall \(placement.identifier, privacy: .public) resolved to \
                \(source.logLabel, privacy: .public)
                """
            )
            phase = .unavailable
            return
        }

        Self.logger.info(
            """
            Paywall \(placement.identifier, privacy: .public) resolved to \
            \(source.logLabel, privacy: .public) — offering \
            \(offering.identifier, privacy: .public), \
            paywall \(Self.paywallPayloadState(of: offering), privacy: .public)
            """
        )
        phase = .ready(offering)
        onPaywallShown()
    }

    /// Whether the resolved offering carries something `PaywallView` can render.
    ///
    /// Three states, not two, because the middle one is a real thing that looks
    /// exactly like a dashboard mistake and is not one (§5j):
    ///
    /// - `present` — a renderable payload is in memory, v2 components or v1
    ///   data. `PaywallView` prefers `internalPaywallComponents` and falls back
    ///   to `validatedPaywall`, so either satisfies it.
    /// - `declared-but-absent` — the backend said this offering *has* a paywall
    ///   (`hasPaywall` is `true`) while neither payload arrived. With remote
    ///   config active the SDK decodes offerings **without** components and
    ///   resolves them from `/v1/config` instead, so a launch that could not
    ///   reach that endpoint leaves the marker without the payload. Fetching
    ///   offerings again does not repair it — the components come from the other
    ///   request — and `PaywallView` then draws its generic default template.
    /// - `none` — genuinely no paywall configured for this offering.
    ///
    /// The distinction is worth its lines because all three log the same
    /// `placement` rung and, in a Release build, the first two are the
    /// difference between the authored paywall and a blank-looking one.
    private static func paywallPayloadState(of offering: Offering) -> String {
        if offering.paywallComponents != nil || offering.paywall != nil {
            return "present"
        }
        return offering.hasPaywall ? "declared-but-absent" : "none"
    }

    // MARK: - States

    /// Shown when no offering could be resolved — offline, or a dashboard that
    /// has no offering for this placement and no current offering either.
    ///
    /// It still names what was on offer (§8 C: a gate names the specific thing
    /// being unlocked), says plainly that it could not be loaded, and offers a
    /// retry. What it deliberately does **not** do is unlock the gated
    /// capability — see `PaywallOfferingSource.resolve`.
    private var unavailableView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(placement.headlineKey.localized)
                .font(.onyxTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("paywall.unavailable.body".localized)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: DesignSystem.Spacing.sm) {
                OnyxButton("action.retry".localized, style: .primary) {
                    phase = .loading
                    Task { await resolveOffering() }
                }

                OnyxButton("action.dismiss".localized, style: .secondary) {
                    dismiss()
                }
            }
            .padding(.top, DesignSystem.Spacing.sm)
        }
        .padding(DesignSystem.Spacing.xl)
    }

    /// §8 B's endowed progress, kept in the app because a dashboard paywall
    /// cannot render the user's own totals.
    private func valueMomentHeader(_ figures: String) -> some View {
        Text(figures)
            .font(.onyxBody)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.background)
    }

    /// "You've logged 12 workouts, 148 sets and 24,300 kg of volume."
    ///
    /// `nil` unless this really is the value moment, so no other placement can
    /// acquire an endowed-progress line by being handed totals.
    private var valueMomentFigures: String? {
        guard placement == .valueMoment, let totals = lifetimeTotals else { return nil }
        return String(
            format: "paywall.value_moment.figures".localized,
            Self.counted(totals.workoutCount),
            Self.counted(totals.completedSetCount),
            Self.counted(Int(totals.volumeKilograms.rounded()))
        )
    }

    /// Hoisted to a `static let` rather than built per call — main-thread rule 2
    /// applies to every view body, not only to the ones inside a list.
    /// `@MainActor` because a shared mutable formatter is only safe while every
    /// access comes from a view body.
    @MainActor
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func counted(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let logger = Logger(subsystem: "app.gymstreak.pro", category: "Paywall")
}
