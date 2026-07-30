//
//  WatchSummaryOverloadPolicy.swift
//  GymStreak
//
//  What the Watch's post-workout recap shows for one qualifying exercise
//  (progressive-overload resurface, ticket 05), as a pure decision over plain
//  values.
//
//  It is pure and duplicated into both targets — the same arrangement as
//  `WatchWorkoutInteractionPolicy` and `ProgressiveOverloadService` — because
//  there is no watch unit-test target: the iOS copy is what the test suite
//  exercises, and the watch keeps a byte-identical copy. KEEP THE TWO IN SYNC.
//
//  The rule this encodes, and the reason it is worth isolating: an applied row
//  never returns to an Apply button. Silently restoring one after iOS overrode
//  the change is how a user applies the same increase twice without ever being
//  told the first one did not stick.
//

import Foundation

/// What an applied overload asked for, kept so the recap can tell "still
/// converging" from "the iPhone overrode it" WITHOUT a second durable ledger.
///
/// The probe is the first affected template set. Once the transaction has left
/// the outgoing queue the effective routine either shows the value this
/// transaction proposed — it applied — or it does not, which can only mean the
/// authoritative routine won.
struct WatchAppliedOverload: Equatable {
    let transactionID: UUID
    let probeSetID: UUID
    let probeWeight: Double
    /// First set's resulting weight, for display. Nil when the target's sets do
    /// not all share one weight, where a single number would misstate the rest.
    let newWeight: Double?
    let targetRepMin: Int
    let isAssistance: Bool
}

/// What the recap shows for one exercise, keyed by the stable routine-slot UUID
/// the workout recorded — never by index or exercise name, so removing or
/// swapping an exercise cannot make a row point at a different one.
struct WatchSummaryOverloadRow: Equatable {
    enum State: Equatable {
        /// Qualified and still unapplied — the one actionable state.
        case actionable
        /// Applied durably on this Watch. Means "committed here for your next
        /// workout", deliberately NOT "saved on iPhone", which may still be
        /// pending while the phone is unreachable.
        case applied(newWeight: Double?, isAssistance: Bool)
        /// The transaction reached iOS and did not survive: the template had
        /// changed there and the authoritative value won.
        case superseded
    }

    let id: UUID
    let state: State
}

enum WatchSummaryOverloadPolicy {

    /// The recap row for one slot, or nil when it gets no overload row at all.
    ///
    /// - Parameters:
    ///   - applied: what was already applied for this slot, from either
    ///     surface. A mid-workout apply therefore arrives at the recap already
    ///     confirmed and can never be offered a second time.
    ///   - isTransactionPending: whether that transaction is still queued. While
    ///     it is, no verdict exists yet, and a pending offline apply must never
    ///     be labelled as overridden.
    ///   - currentProbeWeight: the probe set's weight in the effective routine
    ///     now, or nil if the target is gone entirely.
    ///   - qualifies: ticket 04's shared qualification, evaluated against the
    ///     frozen performance. Mid-workout "Later" deliberately does not
    ///     suppress it: that dismissed one interruption, it did not decline the
    ///     increase.
    ///   - isTargetResolvable: whether the template target and all its set IDs
    ///     still resolve. An actionable row has to be applicable.
    static func state(
        applied: WatchAppliedOverload?,
        isTransactionPending: Bool,
        currentProbeWeight: Double?,
        qualifies: Bool,
        isTargetResolvable: Bool
    ) -> WatchSummaryOverloadRow.State? {
        guard let applied else {
            guard qualifies, isTargetResolvable else { return nil }
            return .actionable
        }
        let confirmed = WatchSummaryOverloadRow.State.applied(
            newWeight: applied.newWeight, isAssistance: applied.isAssistance
        )
        // Not judged yet.
        guard !isTransactionPending else { return confirmed }
        // The target was deleted on iPhone. That is a different story from "your
        // increase was overridden" — and it may well have applied before the
        // deletion — so this stays confirmed rather than inventing a conflict.
        guard let currentProbeWeight else { return confirmed }
        return WatchTemplateSetChange.weightsMatch(currentProbeWeight, applied.probeWeight)
            ? confirmed
            : .superseded
    }
}
