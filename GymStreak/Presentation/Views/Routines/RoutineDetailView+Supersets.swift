//
//  RoutineDetailView+Supersets.swift
//  GymStreak
//
//  Superset support for the routine detail: membership lookups, the link
//  affordance between adjacent cards, the selection edit mode and the per-card
//  context menu. Extracted from RoutineDetailView with redesign v2 to keep the
//  screen file readable — behaviour is unchanged.
//

import SwiftUI

/// Everything a card needs to draw its superset affiliation, resolved once per
/// card. `SupersetLabelProvider.labels(for:)` walks the whole routine, so the
/// card body must not call it (directly or via `supersetColor`) per render.
struct SupersetCardStyling {
    let color: Color?
    let position: Int?
    let total: Int?
    let linePosition: SupersetPosition?

    static let none = SupersetCardStyling(color: nil, position: nil, total: nil, linePosition: nil)
}

extension RoutineDetailView {

    /// Resolves every card's superset styling in ONE pass over the routine.
    /// Doing this per card in a `ForEach` body would filter + sort the whole
    /// routine once per card (O(n²)) and rebuild the label map each time.
    func supersetStyling(for ordered: [RoutineExercise]) -> [UUID: SupersetCardStyling] {
        let labels = SupersetLabelProvider.labels(for: ordered)

        var members: [UUID: [RoutineExercise]] = [:]
        for exercise in ordered {
            guard let supersetId = exercise.supersetId else { continue }
            members[supersetId, default: []].append(exercise)
        }

        var styling: [UUID: SupersetCardStyling] = [:]
        for (supersetId, group) in members {
            let sorted = group.sorted { $0.supersetOrder < $1.supersetOrder }
            let color = labels[supersetId].map { SupersetLabelProvider.color(for: $0) }
            for (index, exercise) in sorted.enumerated() {
                let position = index + 1
                let linePosition: SupersetPosition
                if sorted.count == 1 {
                    linePosition = .only
                } else if position == 1 {
                    linePosition = .first
                } else if position == sorted.count {
                    linePosition = .last
                } else {
                    linePosition = .middle
                }
                styling[exercise.id] = SupersetCardStyling(
                    color: color,
                    position: position,
                    total: sorted.count,
                    linePosition: linePosition
                )
            }
        }
        return styling
    }

    // MARK: - Membership lookups

    /// The last exercise in a superset owns the group's rest time.
    func lastExerciseInSuperset(for exercise: RoutineExercise) -> RoutineExercise? {
        guard let supersetId = exercise.supersetId else { return nil }
        return routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }
            .last
    }

    func supersetRestTime(for exercise: RoutineExercise) -> TimeInterval {
        guard let lastExercise = lastExerciseInSuperset(for: exercise) else {
            return restTime(for: exercise)
        }
        return lastExercise.setsList.first?.restTime ?? 60.0
    }

    func updateSupersetRestTime(for exercise: RoutineExercise, restTime: TimeInterval) {
        guard let lastExercise = lastExerciseInSuperset(for: exercise) else { return }
        updateAllSetsRestTime(for: lastExercise, restTime: restTime)
    }

    var supersetLabels: [UUID: String] {
        SupersetLabelProvider.labels(for: routine.routineExercisesList)
    }

    func supersetLetter(for exercise: RoutineExercise) -> String? {
        guard let supersetId = exercise.supersetId else { return nil }
        return supersetLabels[supersetId]
    }

    // MARK: - Link button between adjacent cards

    /// Whether to show a link button between two adjacent exercises.
    func shouldShowLinkButton(between current: RoutineExercise, and next: RoutineExercise) -> Bool {
        if let id1 = current.supersetId, let id2 = next.supersetId, id1 == id2 {
            return false
        }
        return !current.isInSuperset || !next.isInSuperset
    }

    func linkExercises(_ exercise1: RoutineExercise, _ exercise2: RoutineExercise) {
        if let supersetId = exercise1.supersetId {
            viewModel.addExerciseToSuperset(exercise2, supersetId: supersetId, in: routine)
        } else if let supersetId = exercise2.supersetId {
            viewModel.addExerciseToSuperset(exercise1, supersetId: supersetId, in: routine)
        } else {
            viewModel.createSuperset(from: [exercise1, exercise2], in: routine)
        }
        HapticManager.shared.success()
    }

    // MARK: - Selection edit mode

    func enterSupersetEdit(for supersetId: UUID) {
        let memberIds = routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .map(\.id)
        supersetEditSelection = Set(memberIds)
        collapseCardState()
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = .editing(supersetId)
        }
    }

    func enterSupersetCreate(initiatingExercise: RoutineExercise) {
        supersetEditSelection = [initiatingExercise.id]
        collapseCardState()
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = .creating
        }
    }

    func toggleSupersetSelection(_ exercise: RoutineExercise) {
        withAnimation(DesignSystem.Animation.spring) {
            if supersetEditSelection.contains(exercise.id) {
                supersetEditSelection.remove(exercise.id)
            } else {
                supersetEditSelection.insert(exercise.id)
            }
        }
    }

    /// Whether an exercise can be toggled in the current superset edit mode.
    func canToggleForSuperset(_ exercise: RoutineExercise) -> Bool {
        guard let editMode = supersetEditMode else { return false }
        switch editMode {
        case .editing(let supersetId):
            return exercise.supersetId == supersetId || !exercise.isInSuperset
        case .creating:
            return !exercise.isInSuperset || supersetEditSelection.contains(exercise.id)
        }
    }

    var canApplySupersetEdit: Bool {
        viewModel.canApplySupersetEdit(supersetEditMode, selection: supersetEditSelection)
    }

    /// Apply superset edit changes on Done — the set-algebra diffing itself lives
    /// in RoutinesViewModel; this view only owns the selection UI state.
    func applySupersetEdit() {
        viewModel.applySupersetEdit(supersetEditMode, selection: supersetEditSelection, in: routine)
        HapticManager.shared.success()
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = nil
            supersetEditSelection = []
        }
    }

    func cancelSupersetEdit() {
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = nil
            supersetEditSelection = []
        }
    }

    // MARK: - Selection row

    @ViewBuilder
    func supersetEditRow(for routineExercise: RoutineExercise, display: RoutineExerciseCardDisplay) -> some View {
        let isSelected = supersetEditSelection.contains(routineExercise.id)
        let canToggle = canToggleForSuperset(routineExercise)

        Button {
            if canToggle {
                toggleSupersetSelection(routineExercise)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(
                        isSelected ? DesignSystem.Colors.tint : (canToggle ? Color.secondary : Color.secondary.opacity(0.3))
                    )
                    .contentTransition(.symbolEffect(.replace))

                ExerciseHeaderView(routineExercise: routineExercise, display: display)
            }
            .opacity(canToggle ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
    }

    func supersetEditRowBackground(for exercise: RoutineExercise) -> Color {
        supersetEditSelection.contains(exercise.id) ? DesignSystem.Colors.tint.opacity(0.08) : Color.white.opacity(0.035)
    }

    // MARK: - Context menu

    @ViewBuilder
    func supersetContextMenu(for routineExercise: RoutineExercise) -> some View {
        // If in superset: remove/dissolve options
        if routineExercise.isInSuperset {
            let letter = supersetLetter(for: routineExercise) ?? "?"
            Button {
                viewModel.removeExerciseFromSuperset(routineExercise, in: routine)
            } label: {
                Label(
                    String(format: "superset.remove_from_named".localized, letter),
                    systemImage: "link.badge.minus"
                )
            }

            if let supersetId = routineExercise.supersetId {
                Button(role: .destructive) {
                    viewModel.dissolveSuperset(supersetId, in: routine)
                } label: {
                    Label(
                        String(format: "superset.dissolve_named".localized, letter),
                        systemImage: "link.badge.xmark"
                    )
                }
            }

            Divider()
        }

        // If standalone: create new superset with another exercise
        if !routineExercise.isInSuperset && routine.routineExercisesList.count >= 2 {
            let standaloneExercises = routine.routineExercisesList
                .filter { $0.id != routineExercise.id && !$0.isInSuperset }
                .sorted { $0.order < $1.order }

            if !standaloneExercises.isEmpty {
                Menu {
                    ForEach(standaloneExercises) { other in
                        Button(other.exercise?.name ?? "Unknown") {
                            viewModel.createSuperset(from: [routineExercise, other], in: routine)
                            HapticManager.shared.success()
                        }
                    }
                } label: {
                    Label("superset.create_with".localized, systemImage: "link.badge.plus")
                }
            }

            // Add to existing superset options
            let existingSupersetIds = supersetLabels.keys.sorted { (supersetLabels[$0] ?? "") < (supersetLabels[$1] ?? "") }
            if !existingSupersetIds.isEmpty {
                ForEach(existingSupersetIds, id: \.self) { supersetId in
                    let letter = supersetLabels[supersetId] ?? "?"
                    Button {
                        viewModel.addExerciseToSuperset(routineExercise, supersetId: supersetId, in: routine)
                        HapticManager.shared.success()
                    } label: {
                        Label(
                            String(format: "superset.add_to".localized, letter),
                            systemImage: "plus.circle"
                        )
                    }
                }
            }

            Divider()
        }

        // Manage alternative exercises
        Button {
            openAlternatives(for: routineExercise)
        } label: {
            Label(
                routineExercise.hasAlternatives
                    ? "alternatives.menu.edit".localized(routineExercise.alternativesList.count)
                    : "alternatives.menu.add".localized,
                systemImage: "arrow.triangle.2.circlepath"
            )
        }

        Divider()

        // Delete exercise (undo is offered by the toast)
        Button(role: .destructive) {
            removeExercise(routineExercise)
        } label: {
            Label("exercise.delete".localized, systemImage: "trash")
        }
    }
}
