//
//  RoutineDetailComponents.swift
//  GymStreak
//
//  Supporting views of the redesigned RoutineDetailView: the exercise card
//  header, the expandable set row and the edit-mode wiggle modifier.
//  Extracted from RoutineDetailView.swift with the Routinen & Übungen redesign.
//

import SwiftUI

// MARK: - Exercise card header

struct ExerciseHeaderView: View {
    let routineExercise: RoutineExercise
    var isEditMode: Bool = false
    var showDragHandle: Bool = true
    var supersetPosition: Int? = nil
    var supersetTotal: Int? = nil
    var supersetColor: Color? = nil
    var supersetLinePosition: SupersetPosition? = nil
    var onSupersetAction: (() -> Void)? = nil
    var onEditSets: (() -> Void)? = nil
    var onEditAlternatives: (() -> Void)? = nil

    // Fixed width for the superset indicator area - ensures consistent alignment for all exercises
    private let indicatorAreaWidth: CGFloat = 16
    private let indicatorTrailingSpacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            // FIXED-WIDTH superset indicator area (always present for consistent alignment)
            ZStack {
                if let linePosition = supersetLinePosition {
                    SupersetLineIndicator(position: linePosition, color: supersetColor ?? DesignSystem.Colors.tint)
                }
            }
            .frame(width: indicatorAreaWidth)
            .padding(.trailing, indicatorTrailingSpacing)

            HStack(spacing: 12) {
                if let exercise = routineExercise.exercise {
                    ExerciseAvatarView(
                        muscleGroups: exercise.muscleGroups,
                        equipmentType: exercise.equipmentType
                    )
                    .opacity(isEditMode ? 0.7 : 1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(routineExercise.exercise?.name ?? "Unknown")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .kerning(-0.2)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if routineExercise.hasRepRangeGoal,
                           let min = routineExercise.targetRepMin,
                           let max = routineExercise.targetRepMax {
                            Text("rep_range.sets_with_range".localized(routineExercise.setsList.count, min, max))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .monospacedDigit()
                        } else {
                            Text("routine.sets_count".localized(routineExercise.setsList.count))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .monospacedDigit()
                        }

                        if let exercise = routineExercise.exercise {
                            EquipmentTagView(equipmentType: exercise.equipmentType)
                        }
                    }

                    // Ambient affordance so the alternatives feature is discoverable
                    // before any alternative exists (otherwise it only lives in the menu)
                    if !routineExercise.hasAlternatives, !isEditMode, let editAlternativesAction = onEditAlternatives {
                        Button(action: editAlternativesAction) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption2)
                                Text("alternatives.add".localized)
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.white.opacity(0.35))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("alternatives.menu.add".localized)
                    }
                }

                Spacer()

                // Superset position badge
                if let position = supersetPosition, let total = supersetTotal {
                    SupersetBadge(
                        position: position,
                        total: total,
                        color: supersetColor ?? DesignSystem.Colors.tint
                    )
                }

                // Exercise actions menu (visible in normal mode)
                if !isEditMode && (onSupersetAction != nil || onEditSets != nil) {
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
                        if let editSetsAction = onEditSets {
                            Button {
                                editSetsAction()
                            } label: {
                                Label("exercise.menu.edit_sets".localized, systemImage: "slider.horizontal.3")
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
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }

                // Drag indicator in edit mode (only if showDragHandle is true)
                if isEditMode && showDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Wiggle Animation Modifier

struct WiggleModifier: ViewModifier {
    let isWiggling: Bool
    @State private var wiggleCount: Int = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(wiggleCount > 0 ? (wiggleCount % 2 == 0 ? 2.0 : -2.0) : 0))
            .onChange(of: isWiggling) { _, newValue in
                if newValue {
                    // Perform a single wiggle animation (3 shakes)
                    wiggleCount = 0
                    performWiggle()
                }
            }
    }

    private func performWiggle() {
        // Wiggle 6 times (3 left-right cycles) then stop
        for i in 1...6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    wiggleCount = i
                }
            }
        }
        // Return to center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(DesignSystem.Animation.spring) {
                wiggleCount = 0
            }
        }
    }
}
