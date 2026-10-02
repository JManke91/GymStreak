//
//  CreateRoutineView+Exercises.swift
//  GymStreak
//
//  The Create-Routine screen's exercise list, drawn with the routine detail
//  screen's components so a draft looks exactly like the saved routine:
//  `ExerciseHeaderView` cards on `routineExerciseCardChassis`, supersets inside
//  `SupersetGroupContainer` (connector line + scissors unlink),
//  `SupersetLinkButton` in the gap between two cards, and a "Sort" mode built on
//  the detail screen's sorting rows. Every edit goes through `PendingExerciseList`.
//

import SwiftUI

extension CreateRoutineView {

    // MARK: - Browsing

    /// ScrollView + LazyVStack, like the detail screen's browsing mode — no
    /// `Form`, so no row separators competing with the link control's line.
    var browsingContent: some View {
        ScrollView {
            // The name field sits outside the lazy stack, so a long draft can
            // never recycle the row that holds keyboard focus.
            nameField
                .padding(.horizontal, 16)

            LazyVStack(alignment: .leading, spacing: 0) {
                exercisesHeader

                if draft.isEmpty {
                    emptyState
                } else {
                    exerciseRows
                }

                DashedCreateButton(title: "routine.add_exercise".localized) {
                    showingExercisePicker = true
                }
                .padding(.top, 6)

                Color.clear
                    .frame(height: 40)
            }
            .padding(.horizontal, 16)
            .animation(DesignSystem.Animation.spring, value: draft.exercises.count)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Section label plus the Sort / Done toggle — the detail screen's top-bar
    /// pill, moved here because this screen's navigation bar holds Cancel/Save.
    var exercisesHeader: some View {
        HStack {
            SetsSectionLabel(text: "exercises.title".localized)

            Spacer()

            if draft.exercises.count >= 2 || isSorting {
                Button {
                    toggleSorting()
                } label: {
                    Text(isSorting ? "action.done".localized : "routine.sort".localized)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSorting ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.tint)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(isSorting ? DesignSystem.Colors.tint : DesignSystem.Colors.tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("create_routine.empty.title".localized)
                    .font(.headline)

                Text("create_routine.empty.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    /// One row per unit (standalone card or whole superset), with the link
    /// control in the gap to the next unit. Two members of one superset never
    /// face each other here — they live inside the same group.
    private var exerciseRows: some View {
        ForEach(draft.units) { unit in
            unitRow(unit)

            if let last = unit.exercises.last, draft.canLink(after: last.id) {
                SupersetLinkButton {
                    withAnimation(DesignSystem.Animation.spring) {
                        draft.link(after: last.id)
                    }
                    HapticManager.shared.success()
                }
            }
        }
    }

    @ViewBuilder
    private func unitRow(_ unit: PendingExerciseList.Unit) -> some View {
        if let supersetId = unit.supersetId, let letter = draft.supersetLabels[supersetId] {
            let color = SupersetLabelProvider.color(for: letter)
            let total = unit.exercises.count
            SupersetGroupContainer(
                members: unit.exercises.map {
                    SupersetGroupContainer.Member(id: $0.id, name: $0.exercise.name)
                },
                color: color,
                onUnlink: { memberId in
                    withAnimation(DesignSystem.Animation.spring) {
                        draft.unlink(after: memberId)
                    }
                    HapticManager.shared.success()
                }
            ) {
                ForEach(Array(unit.exercises.enumerated()), id: \.element.id) { index, pending in
                    exerciseCard(pending, position: index + 1, total: total, color: color, letter: letter)

                    // Room on the connector for the unlink control — the
                    // container draws the control itself.
                    if index < total - 1 {
                        SupersetSeamSpacer(memberAboveId: pending.id)
                    }
                }
            }
        } else if let pending = unit.exercises.first {
            exerciseCard(pending, position: nil, total: nil, color: nil, letter: nil)
        }
    }

    /// The detail screen's collapsed card. Tapping opens the set configuration;
    /// long press offers delete, as on the detail screen.
    private func exerciseCard(
        _ pending: PendingRoutineExercise,
        position: Int?,
        total: Int?,
        color: Color?,
        letter: String?
    ) -> some View {
        Button {
            editingExerciseId = pending.id
        } label: {
            HStack(spacing: 10) {
                ExerciseHeaderView(
                    display: RoutineExerciseCardDisplay(pending, in: weightUnit),
                    supersetPosition: position,
                    supersetTotal: total,
                    supersetColor: color,
                    isSupersetMember: color != nil
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(letter.map { "superset.label".localized($0) } ?? "")
        .routineExerciseCardChassis(color: color)
        .contextMenu {
            Button(role: .destructive) {
                deleteExercise(pending.id)
            } label: {
                Label("exercise.delete".localized, systemImage: "trash")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sorting

    /// The detail screen's sorting mode: a real `List` + `.onMove` over units,
    /// so a superset drags as one block and nothing can land between members.
    var sortingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            exercisesHeader
            RoutineSortingHint()

            List {
                ForEach(draft.units) { unit in
                    sortingRow(for: unit)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    HapticManager.shared.light()
                    draft.moveUnits(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func sortingRow(for unit: PendingExerciseList.Unit) -> some View {
        if let supersetId = unit.supersetId, let letter = draft.supersetLabels[supersetId] {
            RoutineSortingGroupRow(
                label: letter,
                color: SupersetLabelProvider.color(for: letter),
                members: unit.exercises.map { pending in
                    RoutineSortingMemberDisplay(
                        id: pending.id,
                        display: RoutineExerciseCardDisplay(pending, in: weightUnit),
                        onRemove: { deleteExercise(pending.id) }
                    )
                }
            )
        } else if let pending = unit.exercises.first {
            RoutineSortingRow(
                display: RoutineExerciseCardDisplay(pending, in: weightUnit),
                onRemove: { deleteExercise(pending.id) }
            )
        }
    }

    // MARK: - Actions

    private func deleteExercise(_ id: UUID) {
        HapticManager.shared.medium()
        withAnimation(DesignSystem.Animation.spring) {
            draft.delete(id: id)
            // Sorting has no empty state — leave it rather than strand the user.
            if draft.exercises.count < 2 { isSorting = false }
        }
    }

    private func toggleSorting() {
        HapticManager.shared.light()
        withAnimation(DesignSystem.Animation.spring) {
            if !isSorting {
                UIAccessibility.post(notification: .announcement, argument: "routine.sort_hint".localized)
            }
            isSorting.toggle()
        }
    }
}
