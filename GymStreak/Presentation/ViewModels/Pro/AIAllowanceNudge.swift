//
//  AIAllowanceNudge.swift
//  GymStreak
//
//  §8 placement D's inline allowance hint, as a value. Shared by the three
//  metered AI surfaces (P3/P4/P5). See docs/pro-subscription.md §5e.
//

import Foundation

/// The finished §8 placement D hint for one metered AI surface: the localized
/// line plus the two numbers `OnyxCapNudge`'s meter draws.
///
/// One struct for all three surfaces rather than one per surface — the shape is
/// identical and only the copy differs, which is why the copy is passed in
/// instead of derived here. `Domain/` holds no localization keys, so
/// `AIAllowancePolicy` returns numbers and the phrasing stays on this side of
/// the boundary.
struct AIAllowanceNudge: Equatable {

    let text: String
    let used: Int
    let limit: Int

    init(text: String, used: Int, limit: Int) {
        self.text = text
        self.used = used
        self.limit = limit
    }

    /// Builds the hint from a gate's nudge state, or `nil` when none belongs on
    /// screen.
    ///
    /// Both strings are `@autoclosure` because this initializer is called from a
    /// computed property a view `body` reads: in the common case the state is
    /// `nil` and no bundle lookup should happen at all.
    ///
    /// - Parameters:
    ///   - remainingFormat: a two-placeholder format receiving **remaining**
    ///     and **limit** — not consumed, because the sentence a user reads
    ///     counts down ("1 of 5 … left this month") while the meter fills up.
    ///   - exhaustedText: the finished line for "nothing left this month".
    init?(
        state: AIAllowancePolicy.NudgeState?,
        remainingFormat: @autoclosure () -> String,
        exhaustedText: @autoclosure () -> String
    ) {
        switch state {
        case .lastRemaining(let consumed, let limit):
            self.init(
                text: String(
                    format: remainingFormat(),
                    AIAllowancePolicy.remaining(consumed: consumed, limit: limit),
                    limit
                ),
                used: consumed,
                limit: limit
            )
        case .exhausted(let consumed, let limit):
            self.init(text: exhaustedText(), used: consumed, limit: limit)
        case nil:
            return nil
        }
    }
}
