//
//  RevenueCatPurchaseGateway+FunnelAttributes.swift
//  GymStreak
//
//  The anonymous funnel buckets, written through the same attribution surface
//  as `founder`. See docs/funnel-instrumentation.md.
//

import Foundation
import OSLog
import RevenueCat

/// Split out of `RevenueCatPurchaseGateway` only for file size — the seam is
/// still the same object, and this is still the one file family allowed to name
/// RevenueCat's attribution surface (docs/pro-subscription.md §3b).
extension RevenueCatPurchaseGateway: FunnelAttributeReporting {

    /// Writes the four anonymous funnel buckets as subscriber attributes, so
    /// every chart in `docs/acquisition-strategy.md` §3 can be segmented on
    /// where a user actually stopped — and filtered to real App Store installs,
    /// which §1.1 showed was the difference between a readable chart and an
    /// unreadable one.
    ///
    /// Siblings of `founder` in every respect that matters: one
    /// `setAttributes` call that records locally and rides the SDK's next
    /// backend request, no identity of any kind on the wire (the app-user ID is
    /// the SDK's own anonymous one and `collectDeviceIdentifiers()` is still
    /// never called), and **nothing anywhere reads them back**.
    ///
    /// Sent as one dictionary rather than four calls so the four values are
    /// always written together: a chart that cross-filters `buildChannel` with
    /// `workoutsCompleted` is reading one moment, not two.
    func report(_ attributes: FunnelAttributes) {
        Purchases.shared.attribution.setAttributes([
            Self.onboardingCompletedAttributeKey: attributes.onboardingCompleted,
            Self.workoutsCompletedAttributeKey: attributes.workoutsCompleted,
            Self.routinesCreatedAttributeKey: attributes.routinesCreated,
            Self.buildChannelAttributeKey: attributes.buildChannel
        ])
        Self.funnelLogger.info(
            """
            Reported funnel: onboardingCompleted=\(attributes.onboardingCompleted, privacy: .public) \
            workoutsCompleted=\(attributes.workoutsCompleted, privacy: .public) \
            routinesCreated=\(attributes.routinesCreated, privacy: .public) \
            buildChannel=\(attributes.buildChannel, privacy: .public)
            """
        )
    }

    /// The four segmentation keys. Spelled here and nowhere else — a dashboard
    /// filter is matched on the literal name, so a second spelling anywhere
    /// would silently create a second, half-populated attribute.
    private static let onboardingCompletedAttributeKey = "onboardingCompleted"
    private static let workoutsCompletedAttributeKey = "workoutsCompleted"
    private static let routinesCreatedAttributeKey = "routinesCreated"
    private static let buildChannelAttributeKey = "buildChannel"

    /// Its own logger rather than the gateway's `founder` one: the entitlement
    /// trail and the funnel trail are read for different questions, and the
    /// category is what separates them in Console. Shares the `Funnel` category
    /// with `FunnelAttributeCoordinator`, which logs the reports it *skipped* —
    /// the two lines only make sense read together.
    nonisolated private static let funnelLogger = Logger(subsystem: "app.gymstreak.pro", category: "Funnel")
}
