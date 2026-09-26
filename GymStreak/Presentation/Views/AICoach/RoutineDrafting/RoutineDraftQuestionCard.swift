//
//  RoutineDraftQuestionCard.swift
//  GymStreak
//
//  The two notes under the drafting sheet's list: the one question it is asking about a
//  draft that lacks something (ticket 04) — with the two ways out of answering, review
//  what is there or discard — and what Create will leave out. See
//  docs/ai-coach-routine-drafting.md §9a and §9c.
//

import SwiftUI

struct RoutineDraftQuestionCard: View {

    let question: String
    /// Set when the last answer's turn failed; the person answers again.
    let error: String?
    /// `false` while the answer is being worked into the draft.
    let isInteractive: Bool
    /// Whether there is anything a review could create — without it, only Discard.
    let canReviewNow: Bool
    let onReviewNow: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                AISparkleView(size: 18, glow: false)
                    .accessibilityHidden(true)
                Text(question)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                if canReviewNow {
                    Button(action: onReviewNow) {
                        Text("ai_coach.routine_draft.question.review_now".localized)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AICoachTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onDiscard) {
                    Text("ai_coach.routine_draft.discard".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .disabled(!isInteractive)
            .opacity(isInteractive ? 1 : 0.4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

/// What Create will do with the rows above it, said before Create is tapped: an exercise
/// the person has not yet pointed at a library entry is left out. Never silent, never
/// invented, and never a dead end either — the row itself is the way to fix it.
///
/// Also used, with its own text, for names the grounding pass dropped because the person
/// never said them (ticket 04).
struct RoutineDraftLeftOutNote: View {

    var title = "ai_coach.routine_draft.left_out.title".localized
    var message = "ai_coach.routine_draft.left_out.body".localized

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

#Preview {
    RoutineDraftQuestionCard(
        question: "Which exercises should this routine include?",
        error: nil,
        isInteractive: true,
        canReviewNow: true,
        onReviewNow: {},
        onDiscard: {}
    )
    .padding()
    .background(Color.black)
}
