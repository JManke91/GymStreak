//
//  FunnelAttributeTracking.swift
//  GymStreak
//
//  The one call every place that moves a user through the funnel makes.
//  See docs/funnel-instrumentation.md.
//

import Foundation

/// Re-reads where this install stands in the funnel and reports it onwards.
///
/// **One method, not four.** The three events that move a user — finishing the
/// tour, creating a routine, completing a workout — each change exactly one
/// attribute, but re-reporting all four is idempotent, costs no network call
/// (`setAttributes` records locally and rides the SDK's next request) and
/// removes the class of bug where a new attribute is added and one of its
/// trigger sites is forgotten. It is the same reasoning that gives
/// `reportFounderStatus` no "have I already sent this" flag.
///
/// **Analytics only, and one-way.** Nothing reads any of these values back —
/// no gate, no entitlement, no UI branch. Reversing that would leak the
/// no-account promise (`docs/monetization-strategy.md` §1) into behaviour, and
/// the protocol having no reads at all is what makes that reviewable.
///
/// `@MainActor` because every state it reads is: the onboarding record, the
/// routine repository and the reporting gateway are all main-actor types. The
/// method is `async` only because the completed-workout count is answered off
/// the main actor by design.
@MainActor
protocol FunnelAttributeTracking: AnyObject {

    /// Reads the four facts and reports them.
    ///
    /// Never on a path a user waits on: it is called from a launch `.task` and
    /// from `Task { … }` at the three event sites, never inline in a view body,
    /// a launch initializer or a purchase flow.
    func reportCurrentState() async
}
