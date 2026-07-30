//
//  RoutineDetailComponents.swift
//  GymStreak
//
//  Supporting views of the redesigned RoutineDetailView: section labels, the
//  exercise card header and the sorting-mode row.
//

import SwiftUI

// MARK: - Shared expanded-card pieces

/// Uppercase micro-label heading a section inside an expanded exercise card
/// (e.g. "SÄTZE", "ALTERNATIVEN"). Shared by the primary variant body and the
/// alternative editors so both read identically.
struct SetsSectionLabel: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.7)
        }
        .foregroundStyle(Color.white.opacity(0.4))
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }
}

// MARK: - Exercise card header

struct ExerciseHeaderView: View {
    let routineExercise: RoutineExercise
    /// Pre-resolved card content — see RoutineExerciseCardDisplay.
    let display: RoutineExerciseCardDisplay
    var supersetPosition: Int? = nil
    var supersetTotal: Int? = nil
    var supersetColor: Color? = nil
    var supersetLinePosition: SupersetPosition? = nil
    var onSupersetAction: (() -> Void)? = nil
    var onEditAlternatives: (() -> Void)? = nil

    // Fixed width for the superset indicator area — keeps every card's avatar
    // on the same x position whether or not it belongs to a superset.
    private let indicatorAreaWidth: CGFloat = 16
    private let indicatorTrailingSpacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if let linePosition = supersetLinePosition {
                    SupersetLineIndicator(position: linePosition, color: supersetColor ?? DesignSystem.Colors.tint)
                }
            }
            .frame(width: indicatorAreaWidth)
            .padding(.trailing, indicatorTrailingSpacing)

            HStack(spacing: 12) {
                if let avatar = display.avatar {
                    ExerciseAvatarView(
                        muscleGroups: avatar.muscleGroups,
                        equipmentType: avatar.equipmentType
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .kerning(-0.2)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // The set summary must never truncate — it is the card's
                    // primary information. The equipment tag is the first thing
                    // to go when the row runs out of width.
                    ViewThatFits(in: .horizontal) {
                        metaRow(showsEquipment: true)
                        metaRow(showsEquipment: false)
                    }
                }

                Spacer(minLength: 4)

                if let position = supersetPosition, let total = supersetTotal {
                    SupersetBadge(
                        position: position,
                        total: total,
                        color: supersetColor ?? DesignSystem.Colors.tint
                    )
                }

                // Kept from v1 (the design has no per-card menu): supersets and
                // the alternatives doorway would otherwise only be reachable via
                // long press.
                if onSupersetAction != nil || onEditAlternatives != nil {
                    Menu {
                        if let supersetAction = onSupersetAction {
                            Button {
                                supersetAction()
                            } label: {
                                Label(
                                    routineExercise.isInSuperset
                                        ? "exercise.menu.edit_superset".localized
                                        : "exercise.menu.superset".localized,
                                    systemImage: routineExercise.isInSuperset ? "pencil.circle" : "link"
                                )
                            }
                        }
                        if let editAlternativesAction = onEditAlternatives {
                            Button {
                                editAlternativesAction()
                            } label: {
                                Label(
                                    routineExercise.hasAlternatives
                                        ? "alternatives.menu.edit".localized(routineExercise.alternativesList.count)
                                        : "alternatives.menu.add".localized,
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func metaRow(showsEquipment: Bool) -> some View {
        HStack(spacing: 8) {
            Text(display.setSummary)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()

            if showsEquipment, let avatar = display.avatar {
                EquipmentTagView(equipmentType: avatar.equipmentType)
                    .fixedSize()
            }

            // Alternatives read as a compact avatar stack — how many and which
            // exercises they are, without a separate chip.
            if !display.alternativeAvatars.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                    ExerciseAvatarStack(
                        exercises: display.alternativeAvatars.map { ($0.muscleGroups, $0.equipmentType) }
                    )
                }
                .accessibilityLabel("alternatives.count".localized(display.alternativeAvatars.count))
            }
        }
    }
}

// MARK: - Sorting mode row

/// Compact row shown while the routine is in sorting mode: drag affordance,
/// avatar, name + set summary, and an immediate remove (undo is offered by a
/// toast). Reordering itself is owned by the enclosing `List`'s `.onMove`, so
/// this row holds no drag state — the handle is a long-press-to-drag hint.
struct RoutineSortingRow: View {
    let display: RoutineExerciseCardDisplay
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))

            if let avatar = display.avatar {
                ExerciseAvatarView(
                    muscleGroups: avatar.muscleGroups,
                    equipmentType: avatar.equipmentType,
                    size: 36,
                    radius: 11
                )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .kerning(-0.2)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(display.setSummary)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .frame(width: 34, height: 34)
                    .background(DesignSystem.Colors.destructive.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("exercise.delete".localized)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Undo toast

/// Floating "removed · undo" toast. Auto-dismisses; the caller owns the timer.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 4)

            Button {
                HapticManager.shared.light()
                onUndo()
            } label: {
                Text("action.undo".localized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .background(DesignSystem.Colors.cardElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
    }
}
