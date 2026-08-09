//
//  RoutineSortingRows.swift
//  GymStreak
//
//  The rows of the routine detail's "Sortieren" mode. Sorting drags whole
//  units, so there are two row kinds: a standalone exercise, and a superset
//  drawn as one framed block containing its members. The block is what makes
//  "this moves together" readable — the list has no way to drop anything
//  between two members, so the grouping has to be visible.
//

import SwiftUI

// MARK: - Standalone row

/// Compact row shown while the routine is in sorting mode: drag affordance,
/// avatar, name + set summary, and an immediate remove (undo is offered by a
/// toast). Reordering itself is owned by the enclosing `List`'s `.onMove`, so
/// this row holds no drag state — the handle is a long-press-to-drag hint.
struct RoutineSortingRow: View {
    let display: RoutineExerciseCardDisplay
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SortingDragHandle()
            SortingRowContent(display: display, onRemove: onRemove)
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

// MARK: - Superset group row

/// One member of a superset as the sorting list draws it. A value struct, so
/// the row never touches a `@Model` object — the remove action is bound to the
/// exercise when the display is built.
struct RoutineSortingMemberDisplay: Identifiable {
    let id: UUID
    let display: RoutineExerciseCardDisplay
    let onRemove: () -> Void
}

/// A whole superset as a single draggable row: the group's letter and colour on
/// top, its members stacked underneath inside one frame. Dragging anywhere on
/// it moves every member together, which is exactly what the frame promises.
/// Members are not individually draggable — unlinking is an explicit action,
/// not a gesture.
struct RoutineSortingGroupRow: View {
    let label: String
    let color: Color
    let members: [RoutineSortingMemberDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SortingDragHandle()

                Image(systemName: "link")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)

                Text("superset.label".localized(label))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(color)

                Text("superset.exercise_count".localized(members.count))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.4))

                Spacer(minLength: 4)
            }

            // A plain stack: a superset holds a handful of exercises and the
            // whole group is one self-sizing `List` row, so there is nothing
            // here for a lazy container to defer.
            VStack(spacing: 6) {
                ForEach(members) { member in
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(color.opacity(0.55))
                            .frame(width: 2.5)

                        SortingRowContent(display: member.display, onRemove: member.onRemove)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("superset.label".localized(label))
    }
}

// MARK: - Shared pieces

/// The long-press-to-drag hint. Purely decorative: `List.onMove` owns the drag.
private struct SortingDragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.35))
    }
}

/// Avatar, name + set summary and the remove button — identical for a
/// standalone row and for a member inside a superset block.
private struct SortingRowContent: View {
    let display: RoutineExerciseCardDisplay
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
    }
}
