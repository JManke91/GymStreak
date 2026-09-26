//
//  RoutineDraftConversation.swift
//  GymStreak
//
//  The asking half of a drafting session (ticket 04): which gap the sheet is asking
//  about, which it already asked about, and the question's text. See
//  docs/ai-coach-routine-drafting.md §9c.
//

import Foundation

/// Which question the drafting sheet is on. What is *missing* is decided by
/// `GroundedRoutineDraft.gaps`; this only decides what to ask next.
struct RoutineDraftConversation {

    /// The gap the current question asks about. Kept while the answer's turn runs, which
    /// is what lets a cancelled or failed follow-up fall back to the same question.
    private(set) var pendingGap: RoutineDraftGap?
    /// The question on screen, composed once when the gap is chosen.
    private(set) var question: String?
    /// Every gap asked about so far. A gap that comes back **unchanged** after its answer
    /// is not asked again — the answer did not fill it, and asking the same question twice
    /// is a loop, not a conversation. It is left to the review, where Swift's default
    /// stands as a value the person can change.
    private var askedGaps: [RoutineDraftGap] = []

    var isAsking: Bool { pendingGap != nil }

    /// Moves to the first of `gaps` not yet asked about in this form.
    ///
    /// - Returns: `false` when there is nothing left to ask — time for the review.
    mutating func askNext(of gaps: [RoutineDraftGap]) -> Bool {
        guard let gap = gaps.first(where: { !askedGaps.contains($0) }) else {
            stopAsking()
            return false
        }
        askedGaps.append(gap)
        pendingGap = gap
        question = RoutineDraftQuestion.text(for: gap)
        return true
    }

    mutating func stopAsking() {
        pendingGap = nil
        question = nil
    }
}

/// The person-facing question for a gap. Swift's words in the app's language, never the
/// model's: the model decides nothing about what is missing, and a question it phrased
/// could carry a "three is typical" default into the one place this surface forbids it.
enum RoutineDraftQuestion {

    static func text(for gap: RoutineDraftGap) -> String {
        switch gap {
        case .exercises:
            "ai_coach.routine_draft.question.exercises".localized
        case .setCounts(let names):
            "ai_coach.routine_draft.question.sets".localized(names.joined(separator: ", "))
        case .name:
            "ai_coach.routine_draft.question.name".localized
        }
    }
}
