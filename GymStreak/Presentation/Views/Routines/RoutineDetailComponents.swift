//
//  RoutineDetailComponents.swift
//  GymStreak
//
//  Supporting views of the redesigned RoutineDetailView: section labels, the
//  exercise card header and the undo toast. The sorting-mode rows live in
//  RoutineSortingRows.swift.
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
    /// Publishes this header's dot position to the enclosing
    /// `SupersetGroupContainer`, which draws the line for the whole group.
    var isSupersetMember: Bool = false
    var onSupersetAction: (() -> Void)? = nil
    var onEditAlternatives: (() -> Void)? = nil

    /// The lane every card keeps free at its leading edge. It keeps all avatars
    /// on the same x whether or not the card is in a superset, and it is the
    /// channel the group's connecting line runs down — so a member card must
    /// indent everything below its header by this much too, or the line crosses
    /// the chip strip and the set list.
    static let connectorLaneWidth: CGFloat = 24

    private let indicatorTrailingSpacing: CGFloat = 8
    private var indicatorAreaWidth: CGFloat { Self.connectorLaneWidth - indicatorTrailingSpacing }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: indicatorAreaWidth)
                .supersetConnectorAnchor(id: routineExercise.id, isActive: isSupersetMember)
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
