//
//  RoutineDraftRowView.swift
//  GymStreak
//
//  One row of the routine-drafting sheet's review list: a drafted exercise the library
//  placed, or one it could not. See docs/ai-coach-routine-drafting.md.
//
//  It takes a finished value struct — no `@Model` read, no formatter, no aggregation in
//  this `body` (CLAUDE.md § "Performance: main thread and rendering").
//

import SwiftUI

struct RoutineDraftRowView: View {

    let row: RoutineDraftRow
    /// `false` while the draft is still streaming, when the list under the finger is
    /// still moving. Only the resolved row's controls read it; the unresolved row's
    /// actions are already guarded by the sheet and the ViewModel.
    let isEditable: Bool
    /// Opens the picker for an unresolved row. Never called for a resolved one.
    let onChoose: () -> Void
    /// Opens `ConfigureExerciseSetsView` for a resolved row. Never called for an
    /// unresolved one.
    let onEdit: () -> Void
    /// Moves the row up (`-1`) or down (`+1`).
    let onMove: (Int) -> Void
    /// Drops the row from the draft.
    let onRemove: () -> Void

    var body: some View {
        if let hint = row.hint {
            unresolved(hint)
        } else {
            resolved
        }
    }

    // MARK: - Resolved

    /// Tapping the row opens its sets; the menu beside it moves or removes it. Side by
    /// side for the same reason as the unresolved row's two buttons.
    private var resolved: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                        if !row.goals.isEmpty {
                            Text(row.goals)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }

                    Spacer(minLength: 8)

                    if isEditable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("ai_coach.routine_draft.edit.hint".localized)

            if isEditable {
                editMenu
            }
        }
        .disabled(!isEditable)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editMenu: some View {
        Menu {
            Button {
                onMove(-1)
            } label: {
                Label("ai_coach.routine_draft.edit.move_up".localized, systemImage: "arrow.up")
            }
            .disabled(!row.canMoveUp)

            Button {
                onMove(1)
            } label: {
                Label("ai_coach.routine_draft.edit.move_down".localized, systemImage: "arrow.down")
            }
            .disabled(!row.canMoveDown)

            Button(role: .destructive, action: onRemove) {
                Label("ai_coach.routine_draft.unresolved.remove".localized, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .accessibilityLabel("ai_coach.routine_draft.edit.actions".localized)
    }

    // MARK: - Unresolved

    /// The name the person used, the figures their description gave it — which survive
    /// being pointed at a library exercise — and what is still missing.
    ///
    /// Two buttons side by side rather than one inside the other: a nested `Button` in
    /// SwiftUI swallows the inner tap.
    private func unresolved(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Button(action: onChoose) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.warning)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                        if !row.goals.isEmpty {
                            Text(row.goals)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        Text(hint)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("ai_coach.routine_draft.unresolved.choose".localized)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ai_coach.routine_draft.unresolved.remove".localized)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.warning.opacity(0.08))
        )
    }
}
