//
//  FunnelAttributeReporting.swift
//  GymStreak
//
//  The seam between the funnel coordinator and RevenueCat's subscriber
//  attributes. See docs/funnel-instrumentation.md.
//

import Foundation

/// Tags this (anonymous) customer with the funnel buckets.
///
/// Lives beside `ProPurchaseGateway` rather than in `Domain/Interfaces/` for the
/// same reason that one does: it is the *purchase layer's* reporting surface,
/// implemented by `RevenueCatPurchaseGateway` and called by one Data-layer
/// coordinator. Presentation never sees it — it calls `FunnelAttributeTracking`,
/// which is the Domain seam.
///
/// **Neither `async` nor `throws`, deliberately**, exactly like
/// `reportFounderStatus(_:)`: a signature that could suspend or fail would
/// invite a caller to wait on analytics. Implementations record the values
/// locally and let the SDK sync them whenever it next talks to the backend.
///
/// A `FunnelAttributes` value, not a dictionary: the bucket spelling is decided
/// once in `Domain/`, and no SDK type crosses this seam in either direction.
@MainActor
protocol FunnelAttributeReporting: AnyObject {
    func report(_ attributes: FunnelAttributes)
}
