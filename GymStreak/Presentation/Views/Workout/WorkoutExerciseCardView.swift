//
//  WorkoutExerciseCardView.swift
//  GymStreak
//
//  The one exercise you are working on: header, its parameters, the set rows.
//  Collapsed exercises are `WorkoutExerciseCollapsedRow`.
//

import SwiftUI

/// The exercise you are on: header, its parameters, and the set rows.
/// The card owns no persistence — every action is handed back to the screen.
struct WorkoutExerciseCardView<SetRows: View>: View {
    let display: WorkoutExerciseDisplay
    let supersetBadge: (position: Int, total: Int, color: Color)?
    let setRows: SetRows
    let onSwap: () -> Void
    let onSwapLockedInfo: () -> Void
    let onRestTimeChange: (TimeInterval) -> Void
    let onAddSet: () -> Void
    let onRemoveExercise: () -> Void

    /// Whether the rest-time editor is open beneath the header.
    @State private var isEditingRestTime = false

    init(
        display: WorkoutExerciseDisplay,
        supersetBadge: (position: Int, total: Int, color: Color)?,
        @ViewBuilder setRows: () -> SetRows,
        onSwap: @escaping () -> Void,
        onSwapLockedInfo: @escaping () -> Void,
        onRestTimeChange: @escaping (TimeInterval) -> Void,
        onAddSet: @escaping () -> Void,
        onRemoveExercise: @escaping () -> Void
    ) {
        self.display = display
        self.supersetBadge = supersetBadge
        self.setRows = setRows()
        self.onSwap = onSwap
        self.onSwapLockedInfo = onSwapLockedInfo
        self.onRestTimeChange = onRestTimeChange
        self.onAddSet = onAddSet
        self.onRemoveExercise = onRemoveExercise
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // A superset's rest belongs to the round, not the exercise — its
            // group header owns that control, so the chip is hidden here.
            if !display.isInSuperset {
                restChip
            }

            if isEditingRestTime {
                RestTimeInlineEditor(restTime: display.restTime) { newValue in
                    onRestTimeChange(newValue)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(spacing: 8) {
                setRows
            }

            addSetButton
        }
        .padding(14)
        .background(DesignSystem.Colors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ExerciseAvatarView(
                    muscleGroups: display.muscleGroups,
                    equipmentType: display.equipmentType,
                    size: 44,
                    radius: 13
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(display.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    metaRow
                }

                Spacer(minLength: 0)

                if let supersetBadge {
                    SupersetBadge(
                        position: supersetBadge.position,
                        total: supersetBadge.total,
                        color: supersetBadge.color
                    )
                }

                swapButton
                exerciseMenu
            }

            // Persists for the rest of the workout so history stays readable;
            // tapping it reopens the picker, or explains why it is locked.
            if let swappedFrom = display.swappedFromName {
                Button {
                    display.canSwap ? onSwap() : onSwapLockedInfo()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Text("workout.swap.swapped_from".localized(swappedFrom))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text("workout.exercise.sets_done".localized(display.completedSets, display.totalSets))
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DesignSystem.Colors.tint)
                .fixedSize()

            if let repRange = display.repRangeText {
                separator
                Text("workout.exercise.rep_goal".localized(repRange))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
    }

    /// The rest time is a **value the user needs to read at a glance**, so it gets
    /// its own full-width row rather than a slot at the end of the meta line.
    /// Sharing that line with the name, the set count and the rep goal left the
    /// chip a few points wide next to a swap pill, and SwiftUI truncated its
    /// label and value away — leaving a bare timer glyph that gave no clue what
    /// the rest actually was. `fixedSize` makes that failure mode impossible.
    private var restChip: some View {
        ParameterChipButton(
            icon: "timer",
            label: "rest_timer.rest_short".localized,
            value: display.restTime > 0
                ? TimeFormatting.formatRestTime(display.restTime)
                : "rest_timer.off".localized,
            isActive: isEditingRestTime
        ) {
            HapticManager.shared.light()
            withAnimation(DesignSystem.Animation.spring) {
                isEditingRestTime.toggle()
            }
        }
        .fixedSize()
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.white.opacity(0.18))
    }

    /// Deliberately labeled, not the design mock's bare glyph: a lone
    /// `arrow.triangle.2.circlepath` was tested before and read as refresh/sync
    /// (see docs/alternative-exercises.md). The label is what makes it a swap.
    @ViewBuilder
    private var swapButton: some View {
        if display.canSwap || display.isSwapLocked {
            Button {
                display.canSwap ? onSwap() : onSwapLockedInfo()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: display.canSwap ? "arrow.triangle.2.circlepath" : "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("workout.swap.button".localized)
                        .font(.system(size: 11.5, weight: .bold))
                }
                .foregroundStyle(display.canSwap ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(display.canSwap ? DesignSystem.Colors.tint : Color.white.opacity(0.1))
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                display.canSwap
                    ? "workout.swap.accessibility".localized(display.name)
                    : "workout.swap.locked.title".localized
            )
        }
    }

    private var exerciseMenu: some View {
        Menu {
            Button(role: .destructive, action: onRemoveExercise) {
                Label("delete_exercise.remove".localized, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("workout.exercise.actions".localized(display.name))
    }

    private var addSetButton: some View {
        Button {
            HapticManager.shared.light()
            onAddSet()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("exercise.add_set".localized)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color.white.opacity(0.14))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("accessibility.add_set".localized(display.name))
        .accessibilityHint("accessibility.add_set.hint".localized)
    }
}
