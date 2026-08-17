//
//  CustomerCenterEvent.swift
//  GymStreak
//
//  What happened inside the Customer Center, as a value that can be logged.
//  See docs/pro-subscription.md §5j.
//

import Foundation
import OSLog

/// One thing the user did in `CustomerCenterView`.
///
/// The Customer Center is a screen the app does not draw and cannot inspect:
/// restores, cancellations, refund requests and survey answers all happen inside
/// it. Without this, a support question ("I cancelled and it still says Pro",
/// "my restore did nothing") has no evidence behind it at all — the app would
/// know only the entitlement it ended up with, never what the user tried.
///
/// A value with a `message`, rather than `logger.info(…)` at each call site, for
/// the usual reason in this codebase: the mapping is the part worth asserting,
/// and a closure inside a view modifier cannot be.
///
/// **No RevenueCat type appears here.** The presenting row converts the SDK's
/// payloads to strings before constructing a case, so this stays in Presentation
/// with no SDK import and stays assertable without one.
enum CustomerCenterEvent: Equatable {

    case restoreStarted
    case restoreCompleted
    case restoreFailed(String)
    case showingManageSubscriptions
    case refundRequestStarted(productID: String)
    case refundRequestCompleted(productID: String, status: String)
    case feedbackSurveyCompleted(optionID: String)
    case managementOptionSelected(String)

    /// The log line. Prefixed uniformly so the whole Customer Center session
    /// greps out of a sysdiagnose as one sequence.
    var message: String {
        switch self {
        case .restoreStarted:
            "restore started"
        case .restoreCompleted:
            "restore completed"
        case .restoreFailed(let error):
            "restore failed: \(error)"
        case .showingManageSubscriptions:
            "showing manage subscriptions"
        case .refundRequestStarted(let productID):
            "refund request started for \(productID)"
        case .refundRequestCompleted(let productID, let status):
            "refund request for \(productID) completed: \(status)"
        case .feedbackSurveyCompleted(let optionID):
            "feedback survey completed: \(optionID)"
        case .managementOptionSelected(let option):
            "management option selected: \(option)"
        }
    }

    /// Records the event.
    ///
    /// `.public` because nothing here identifies a person: product identifiers,
    /// refund statuses and survey option ids are all app-side constants, and the
    /// app has no account to tie them to (§9.3).
    func log() {
        Self.logger.info("Customer Center: \(message, privacy: .public)")
    }

    private static let logger = Logger(subsystem: "app.gymstreak.pro", category: "CustomerCenter")
}
