//
//  RoutineDraftFooter.swift
//  GymStreak
//
//  The routine-drafting sheet's bottom bar: the allowance hint, and then either the
//  description field (describe / draft / retry) or the Discard–Create pair (review).
//  Split out of `RoutineDraftSheet.swift` to keep both files inside the project's
//  300-line convention. See docs/ai-coach-routine-drafting.md.
//

import SwiftUI

/// Which control the bar shows is derived from one question — is there something a
/// Create button could actually write — so a draft in which nothing resolved keeps the
/// description field rather than offering a Create that would do nothing.
struct RoutineDraftFooter: View {

    @Bindable var viewModel: RoutineDraftViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.06))

            // §8 placement D — the shared Coach allowance hint. Blocks nothing, and it
            // sits above the field so it is on screen *before* the send that meters.
            if let nudge = viewModel.allowanceNudge {
                OnyxCapNudge(text: nudge.text, used: nudge.used, limit: nudge.limit)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if viewModel.canCreate {
                reviewActions
            } else {
                descriptionField
            }
        }
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Review

    private var reviewActions: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.discard()
            } label: {
                Text("ai_coach.routine_draft.discard".localized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            Button {
                viewModel.createRoutine()
            } label: {
                Text("ai_coach.routine_draft.create".localized)
                    .font(.system(size: 15, weight: .bold))
                    // Never white on the tint — `textOnTint` exists for exactly this.
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AICoachTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Describing

    private var descriptionField: some View {
        HStack(spacing: 10) {
            TextField(
                "ai_coach.routine_draft.input.placeholder".localized,
                text: $viewModel.descriptionText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Color.white)
            .lineLimit(1...5)
            .disabled(viewModel.isDrafting)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            submitButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Doubles as the stop control while a draft streams — cancelling writes nothing and
    /// gives the allowance unit back.
    private var submitButton: some View {
        Button {
            if viewModel.isDrafting {
                viewModel.cancelDrafting()
            } else {
                viewModel.submit()
            }
        } label: {
            Image(systemName: viewModel.isDrafting ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        viewModel.isDrafting || viewModel.canSubmit
                            ? AICoachTheme.accent
                            : AICoachTheme.accent.opacity(0.3)
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isDrafting && !viewModel.canSubmit)
        .accessibilityLabel(
            viewModel.isDrafting
                ? "ai_coach.routine_draft.stop".localized
                : "ai_coach.routine_draft.submit".localized
        )
    }
}
