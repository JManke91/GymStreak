import SwiftUI

struct RoutineDetailView: View {
    @Bindable var routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddExercise = false
    @State private var showingDeleteAlert = false
    @State private var showingDeleteExerciseAlert = false
    @State private var exercisePendingDeletion: RoutineExercise?
    @State private var showingActiveWorkout = false
    @State private var showingRenameAlert = false
    @State private var renameText: String = ""
    @State private var expandedExerciseId: UUID?
    @State private var expandedSetId: UUID?
    @State private var editingReps: Int = 10
    @State private var editingWeight: Double = 0.0
    @State private var initialReps: Int = 10
    @State private var initialWeight: Double = 0.0
    @State private var repsBannerDismissedForExercise: [UUID: Bool] = [:]
    @State private var weightBannerDismissedForExercise: [UUID: Bool] = [:]
    @State private var currentRoutineExercise: RoutineExercise?
    @State private var restTimerExpandedForExercise: [UUID: Bool] = [:]
    @State private var isEditMode: Bool = false
    @State private var supersetEditMode: SupersetEditMode? = nil
    @State private var supersetEditSelection: Set<UUID> = []
    @AppStorage("hasSeenReorderHint") private var hasSeenReorderHint = false
    @State private var showReorderHint = false
    @State private var setEditExerciseId: UUID? = nil
    @State private var addAlternativeTarget: RoutineExercise? = nil
    /// Which variant the expanded exercise card is focused on: nil = the primary
    /// exercise; otherwise the focused alternative's id. Drives the single-variant
    /// card body (only that exercise's config is shown).
    @State private var focusedAlternativeId: UUID? = nil
    @State private var draggingId: UUID? = nil
    @State private var repRangeExpandedForExercise: [UUID: Bool] = [:]
    @State private var overloadBannerDismissedForExercise: [UUID: Bool] = [:]
    @State private var selectedExerciseForOverload: RoutineExercise?
    @State private var showingSchedulePlanner = false
    // Alternatives browse sheet (one-tap entry from the info chip) + the jump it
    // hands back: expand the card + that alternative's inline editor, scrolled in.
    @State private var browseAlternativesTarget: RoutineExercise?
    @State private var pendingExpandExerciseId: UUID?
    @State private var pendingExpandAlternativeId: UUID?
    @State private var pendingAddTarget: RoutineExercise?
    @State private var scrollToExerciseId: UUID?

    // Helper function to get rest time for an exercise
    private func restTime(for exercise: RoutineExercise) -> TimeInterval {
        exercise.setsList.first?.restTime ?? 0.0
    }

    // Helper to get superset position info for an exercise
    private func supersetInfo(for exercise: RoutineExercise) -> (position: Int, total: Int)? {
        guard let supersetId = exercise.supersetId else { return nil }
        let supersetExercises = routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }
        guard let index = supersetExercises.firstIndex(where: { $0.id == exercise.id }) else { return nil }
        return (position: index + 1, total: supersetExercises.count)
    }

    // Check if this exercise is the first in its superset
    private func isFirstInSuperset(_ exercise: RoutineExercise) -> Bool {
        guard let info = supersetInfo(for: exercise) else { return false }
        return info.position == 1
    }

    // Get the last exercise in a superset for rest time config
    private func lastExerciseInSuperset(for exercise: RoutineExercise) -> RoutineExercise? {
        guard let supersetId = exercise.supersetId else { return nil }
        return routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }
            .last
    }

    // Get the superset rest time (from the last exercise's first set)
    private func supersetRestTime(for exercise: RoutineExercise) -> TimeInterval {
        guard let lastExercise = lastExerciseInSuperset(for: exercise) else {
            return restTime(for: exercise)
        }
        return lastExercise.setsList.first?.restTime ?? 60.0
    }

    // Update rest time for all sets of the last exercise in a superset
    private func updateSupersetRestTime(for exercise: RoutineExercise, restTime: TimeInterval) {
        guard let lastExercise = lastExerciseInSuperset(for: exercise) else { return }
        updateAllSetsRestTime(for: lastExercise, restTime: restTime)
    }

    // Helper to get superset line position for visual indicator
    private func supersetLinePosition(for exercise: RoutineExercise) -> SupersetPosition? {
        guard let info = supersetInfo(for: exercise) else { return nil }
        if info.total == 1 {
            return .only
        } else if info.position == 1 {
            return .first
        } else if info.position == info.total {
            return .last
        } else {
            return .middle
        }
    }

    // Computed superset labels for the current routine
    private var supersetLabels: [UUID: String] {
        SupersetLabelProvider.labels(for: routine.routineExercisesList)
    }

    // Get superset color for an exercise
    private func supersetColor(for exercise: RoutineExercise) -> Color? {
        guard let supersetId = exercise.supersetId,
              let letter = supersetLabels[supersetId] else { return nil }
        return SupersetLabelProvider.color(for: letter)
    }

    // Get superset letter for an exercise
    private func supersetLetter(for exercise: RoutineExercise) -> String? {
        guard let supersetId = exercise.supersetId else { return nil }
        return supersetLabels[supersetId]
    }

    // MARK: - Superset Link Button Helpers

    /// Whether to show a link button between two adjacent exercises
    private func shouldShowLinkButton(between current: RoutineExercise, and next: RoutineExercise) -> Bool {
        // Don't show if both are in the same superset (already linked)
        if let id1 = current.supersetId, let id2 = next.supersetId, id1 == id2 {
            return false
        }
        // Show if at least one is standalone
        return !current.isInSuperset || !next.isInSuperset
    }

    /// Link two adjacent exercises into a superset
    private func linkExercises(_ exercise1: RoutineExercise, _ exercise2: RoutineExercise) {
        if let supersetId = exercise1.supersetId {
            viewModel.addExerciseToSuperset(exercise2, supersetId: supersetId, in: routine)
        } else if let supersetId = exercise2.supersetId {
            viewModel.addExerciseToSuperset(exercise1, supersetId: supersetId, in: routine)
        } else {
            viewModel.createSuperset(from: [exercise1, exercise2], in: routine)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Superset Edit Mode

    /// Enter superset edit mode for an existing superset
    private func enterSupersetEdit(for supersetId: UUID) {
        let memberIds = routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .map(\.id)
        supersetEditSelection = Set(memberIds)
        expandedExerciseId = nil
        expandedSetId = nil
        setEditExerciseId = nil
        focusedAlternativeId = nil
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = .editing(supersetId)
        }
    }

    /// Enter superset edit mode to create a new superset
    private func enterSupersetCreate(initiatingExercise: RoutineExercise) {
        supersetEditSelection = [initiatingExercise.id]
        expandedExerciseId = nil
        expandedSetId = nil
        setEditExerciseId = nil
        focusedAlternativeId = nil
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = .creating
        }
    }

    /// Toggle an exercise's membership in the superset selection
    private func toggleSupersetSelection(_ exercise: RoutineExercise) {
        withAnimation(DesignSystem.Animation.spring) {
            if supersetEditSelection.contains(exercise.id) {
                supersetEditSelection.remove(exercise.id)
            } else {
                supersetEditSelection.insert(exercise.id)
            }
        }
    }

    /// Whether an exercise can be toggled in the current superset edit mode
    private func canToggleForSuperset(_ exercise: RoutineExercise) -> Bool {
        guard let editMode = supersetEditMode else { return false }
        switch editMode {
        case .editing(let supersetId):
            return exercise.supersetId == supersetId || !exercise.isInSuperset
        case .creating:
            return !exercise.isInSuperset || supersetEditSelection.contains(exercise.id)
        }
    }

    /// Whether the Done button should be enabled in superset edit mode
    private var canApplySupersetEdit: Bool {
        viewModel.canApplySupersetEdit(supersetEditMode, selection: supersetEditSelection)
    }

    /// Apply superset edit changes on Done — the set-algebra diffing itself lives in
    /// RoutinesViewModel; this view only owns the selection UI state.
    private func applySupersetEdit() {
        viewModel.applySupersetEdit(supersetEditMode, selection: supersetEditSelection, in: routine)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = nil
            supersetEditSelection = []
        }
    }

    /// Cancel superset edit mode
    private func cancelSupersetEdit() {
        withAnimation(DesignSystem.Animation.spring) {
            supersetEditMode = nil
            supersetEditSelection = []
        }
    }

    // MARK: - Set Reorder Mode

    private func enterSetEditMode(for routineExercise: RoutineExercise) {
        guard !isEditMode, supersetEditMode == nil else { return }
        withAnimation(DesignSystem.Animation.spring) {
            expandedExerciseId = routineExercise.id
            expandedSetId = nil
            setEditExerciseId = routineExercise.id
            focusedAlternativeId = nil
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func exitSetEditMode() {
        withAnimation(DesignSystem.Animation.spring) {
            setEditExerciseId = nil
        }
    }

    // MARK: - Alternatives (add doorway)

    /// Expand the card focused on its first alternative (so the variant editor is
    /// shown directly); for an exercise with no alternatives yet, jump straight
    /// into the add-alternative picker.
    private func openAlternatives(for routineExercise: RoutineExercise) {
        guard !isEditMode, supersetEditMode == nil else { return }
        withAnimation(DesignSystem.Animation.spring) {
            expandedExerciseId = routineExercise.id
            expandedSetId = nil
            setEditExerciseId = nil
            focusedAlternativeId = routineExercise.alternativesList.first?.id
        }
        if !routineExercise.hasAlternatives {
            addAlternativeTarget = routineExercise
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Runs after the alternatives-browse sheet dismisses. Either chains into the
    /// add-alternative picker, or jumps to the chosen alternative's inline editor
    /// (expand the card + that alternative, then scroll the card into view).
    private func applyPendingBrowseAction() {
        if let addTarget = pendingAddTarget {
            pendingAddTarget = nil
            // Expand the target card first so the picker's onAdded (which expands
            // the freshly added alternative's inline editor) lands on a visible card.
            withAnimation(DesignSystem.Animation.spring) {
                expandedExerciseId = addTarget.id
                expandedSetId = nil
                setEditExerciseId = nil
                focusedAlternativeId = nil
            }
            addAlternativeTarget = addTarget
            scrollToExerciseId = addTarget.id
            return
        }
        guard let exerciseId = pendingExpandExerciseId,
              let alternativeId = pendingExpandAlternativeId else { return }
        pendingExpandExerciseId = nil
        pendingExpandAlternativeId = nil
        withAnimation(DesignSystem.Animation.spring) {
            expandedExerciseId = exerciseId
            expandedSetId = nil
            setEditExerciseId = nil
            focusedAlternativeId = alternativeId
        }
        scrollToExerciseId = exerciseId
    }

    private func moveSetUp(at index: Int, for routineExercise: RoutineExercise) {
        guard index > 0 else { return }
        viewModel.moveExerciseSets(from: IndexSet(integer: index), to: index - 1, for: routineExercise)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func moveSetDown(at index: Int, for routineExercise: RoutineExercise) {
        guard index < routineExercise.setsList.count - 1 else { return }
        viewModel.moveExerciseSets(from: IndexSet(integer: index), to: index + 2, for: routineExercise)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Set Content Views

    @ViewBuilder
    private func normalSetContent(for routineExercise: RoutineExercise) -> some View {
        let focusedAlternative = routineExercise.alternativesList.first { $0.id == focusedAlternativeId }

        // Variant switcher: the primary exercise + each alternative as peer pills.
        // Selecting one focuses that variant so the body shows ONLY that exercise —
        // a routine exercise is one "slot" you configure one variant at a time.
        if routineExercise.hasAlternatives {
            ExerciseVariantSwitcher(
                routineExercise: routineExercise,
                focusedAlternativeId: $focusedAlternativeId,
                onAddAlternative: { addAlternativeTarget = routineExercise }
            )
            .padding(.bottom, 2)
        }

        if let focusedAlternative {
            AlternativeFocusedEditor(
                alternative: focusedAlternative,
                viewModel: viewModel,
                onRemoved: {
                    withAnimation(DesignSystem.Animation.spring) { focusedAlternativeId = nil }
                }
            )
        } else {
            primarySetContent(for: routineExercise)
        }
    }

    @ViewBuilder
    private func primarySetContent(for routineExercise: RoutineExercise) -> some View {
        // Rest Timer Configuration
        if routineExercise.isInSuperset {
            if isFirstInSuperset(routineExercise) {
                SupersetRestTimerConfig(
                    restTime: Binding(
                        get: { supersetRestTime(for: routineExercise) },
                        set: { newValue in
                            updateSupersetRestTime(for: routineExercise, restTime: newValue)
                        }
                    ),
                    isExpanded: Binding(
                        get: { restTimerExpandedForExercise[routineExercise.id] ?? false },
                        set: { restTimerExpandedForExercise[routineExercise.id] = $0 }
                    )
                )
            }
        } else {
            RestTimerConfigView(
                restTime: Binding(
                    get: { restTime(for: routineExercise) },
                    set: { newValue in
                        updateAllSetsRestTime(for: routineExercise, restTime: newValue)
                    }
                ),
                isExpanded: Binding(
                    get: { restTimerExpandedForExercise[routineExercise.id] ?? false },
                    set: { restTimerExpandedForExercise[routineExercise.id] = $0 }
                ),
                showToggle: true
            )
        }

        // Rep Range Configuration
        RepRangeConfigView(
            targetRepMin: Binding(
                get: { routineExercise.targetRepMin },
                set: { routineExercise.targetRepMin = $0 }
            ),
            targetRepMax: Binding(
                get: { routineExercise.targetRepMax },
                set: { routineExercise.targetRepMax = $0 }
            ),
            isExpanded: Binding(
                get: { repRangeExpandedForExercise[routineExercise.id] ?? false },
                set: { repRangeExpandedForExercise[routineExercise.id] = $0 }
            ),
            onRepRangeChange: { min, max in
                viewModel.updateRepRange(for: routineExercise, min: min, max: max)
            }
        )

        // Progressive Overload Banner
        if routineExercise.allSetsAtUpperLimit,
           !(overloadBannerDismissedForExercise[routineExercise.id] ?? false) {
            ProgressiveOverloadBanner(
                targetRepMax: routineExercise.targetRepMax ?? 0,
                isAssistance: routineExercise.exercise?.loadBehavior.isCounterweightAssistance == true,
                onIncrease: {
                    selectedExerciseForOverload = routineExercise
                },
                onDismiss: {
                    withAnimation(DesignSystem.Animation.spring) {
                        overloadBannerDismissedForExercise[routineExercise.id] = true
                    }
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        }

        SetsSectionLabel(text: "routine.section.sets".localized)

        ForEach(Array(routineExercise.setsList.sorted(by: { $0.order < $1.order }).enumerated()), id: \.element.id) { index, set in
            RoutineSetRowView(
                set: set,
                index: index,
                isExpanded: expandedSetId == set.id,
                editingReps: $editingReps,
                editingWeight: $editingWeight,
                initialReps: initialReps,
                initialWeight: initialWeight,
                hasMultipleSets: routineExercise.setsList.count > 1,
                repsBannerDismissed: repsBannerDismissedForExercise[routineExercise.id] ?? false,
                weightBannerDismissed: weightBannerDismissedForExercise[routineExercise.id] ?? false,
                totalSets: routineExercise.setsList.count,
                targetRepMin: routineExercise.targetRepMin,
                targetRepMax: routineExercise.targetRepMax,
                onTap: {
                    withAnimation(DesignSystem.Animation.spring) {
                        if expandedSetId == set.id {
                            saveCurrentExpandedSet()
                            expandedSetId = nil
                            currentRoutineExercise = nil
                        } else {
                            saveCurrentExpandedSet()
                            expandedSetId = set.id
                            editingReps = set.reps
                            editingWeight = set.weight
                            initialReps = set.reps
                            initialWeight = set.weight
                            currentRoutineExercise = routineExercise
                            repsBannerDismissedForExercise[routineExercise.id] = false
                            weightBannerDismissedForExercise[routineExercise.id] = false
                        }
                    }
                },
                onUpdate: { reps, weight in
                    guard expandedSetId == set.id else { return }
                    handleSetUpdate(
                        set: set,
                        reps: reps,
                        weight: weight,
                        routineExercise: routineExercise,
                        applyToAll: false
                    )
                },
                onApplyRepsToAll: {
                    withAnimation(DesignSystem.Animation.spring) {
                        handleApplyRepsToAll(
                            reps: editingReps,
                            routineExercise: routineExercise
                        )
                        repsBannerDismissedForExercise[routineExercise.id] = true
                        initialReps = editingReps
                    }
                },
                onApplyWeightToAll: {
                    withAnimation(DesignSystem.Animation.spring) {
                        handleApplyWeightToAll(
                            weight: editingWeight,
                            routineExercise: routineExercise
                        )
                        weightBannerDismissedForExercise[routineExercise.id] = true
                        initialWeight = editingWeight
                    }
                },
                onDismissRepsBanner: {
                    withAnimation(DesignSystem.Animation.spring) {
                        repsBannerDismissedForExercise[routineExercise.id] = true
                    }
                },
                onDismissWeightBanner: {
                    withAnimation(DesignSystem.Animation.spring) {
                        weightBannerDismissedForExercise[routineExercise.id] = true
                    }
                },
                onDelete: {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeSet(set, from: routineExercise)
                        if expandedSetId == set.id {
                            expandedSetId = nil
                        }
                    }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // Inline add-set — same affordance as the alternative editor, expanding
        // the new set's editor right away.
        AddSetInlineButton {
            withAnimation(DesignSystem.Animation.spring) {
                saveCurrentExpandedSet()
                let newSet = viewModel.addSet(to: routineExercise)
                expandedSetId = newSet.id
                editingReps = newSet.reps
                editingWeight = newSet.weight
                initialReps = newSet.reps
                initialWeight = newSet.weight
                currentRoutineExercise = routineExercise
                repsBannerDismissedForExercise[routineExercise.id] = false
                weightBannerDismissedForExercise[routineExercise.id] = false
            }
        }

        // First alternative for this exercise is added here; once any exist, the
        // add affordance moves into the variant switcher's "+" pill above.
        if !routineExercise.hasAlternatives {
            DashedCreateButton(title: "alternatives.add".localized, tinted: true) {
                addAlternativeTarget = routineExercise
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func setEditContent(for routineExercise: RoutineExercise) -> some View {
        let sortedSets = routineExercise.setsList.sorted(by: { $0.order < $1.order })
        let setCount = sortedSets.count
        ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
            HStack(spacing: 8) {
                // Delete button
                Button {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeSet(set, from: routineExercise)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .red)
                        .symbolRenderingMode(.palette)
                }
                .buttonStyle(.plain)

                Text("\(index + 1)")
                    .font(.system(size: 11.5, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 24, height: 24)
                    .background(DesignSystem.Colors.tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    Text("set.reps".localized(set.reps))
                    Text("×")
                        .foregroundStyle(.secondary)
                    Text("set.weight".localized(set.weight))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

                Spacer()

                if setCount > 1 {
                    HStack(spacing: 4) {
                        Button { moveSetUp(at: index, for: routineExercise) } label: {
                            Image(systemName: "chevron.up")
                                .font(.body.weight(.medium))
                                .foregroundStyle(index > 0 ? .primary : .quaternary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .disabled(index == 0)
                        .buttonStyle(.plain)

                        Button { moveSetDown(at: index, for: routineExercise) } label: {
                            Image(systemName: "chevron.down")
                                .font(.body.weight(.medium))
                                .foregroundStyle(index < setCount - 1 ? .primary : .quaternary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .disabled(index >= setCount - 1)
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
        }

        // Add Set button
        Button {
            withAnimation(DesignSystem.Animation.spring) {
                _ = viewModel.addSet(to: routineExercise)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("exercise.add_set".localized)
                    .font(.system(size: 12.5, weight: .bold))
            }
            .foregroundStyle(DesignSystem.Colors.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.tint.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(DesignSystem.Colors.tint.opacity(0.3))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)

        // Done button
        Button {
            exitSetEditMode()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("action.done".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DesignSystem.Colors.tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Superset Edit Mode Row
    @ViewBuilder
    private func supersetEditRow(for routineExercise: RoutineExercise) -> some View {
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

                ExerciseHeaderView(
                    routineExercise: routineExercise,
                    isEditMode: false,
                    showDragHandle: false
                )
            }
            .opacity(canToggle ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
    }

    /// Card background for superset edit mode
    private func supersetEditRowBackground(for exercise: RoutineExercise) -> Color {
        supersetEditSelection.contains(exercise.id) ? DesignSystem.Colors.tint.opacity(0.08) : Color.white.opacity(0.035)
    }

    // MARK: - Superset Context Menu
    @ViewBuilder
    private func supersetContextMenu(for routineExercise: RoutineExercise) -> some View {
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
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

        // Edit sets (add, delete, reorder)
        Button {
            enterSetEditMode(for: routineExercise)
        } label: {
            Label("exercise.menu.edit_sets".localized, systemImage: "slider.horizontal.3")
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

        // Delete exercise
        Button(role: .destructive) {
            exercisePendingDeletion = routineExercise
            showingDeleteExerciseAlert = true
        } label: {
            Label("exercise.delete".localized, systemImage: "trash")
        }
    }

    // MARK: - Edit Mode Row View Builder
    @ViewBuilder
    private func editModeRow(for routineExercise: RoutineExercise) -> some View {
        HStack(spacing: 12) {
            Button {
                exercisePendingDeletion = routineExercise
                showingDeleteExerciseAlert = true
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .red)
                    .symbolRenderingMode(.palette)
            }
            .buttonStyle(.plain)

            // Exercise header with superset info
            let info = supersetInfo(for: routineExercise)
            let linePos = supersetLinePosition(for: routineExercise)
            let color = supersetColor(for: routineExercise)
            ExerciseHeaderView(
                routineExercise: routineExercise,
                isEditMode: true,
                supersetPosition: info?.position,
                supersetTotal: info?.total,
                supersetColor: color,
                supersetLinePosition: linePos
            )
        }
    }

    // Card background color using per-group superset color
    private func cardBackgroundColor(for routineExercise: RoutineExercise) -> Color {
        guard let color = supersetColor(for: routineExercise) else { return Color.white.opacity(0.035) }
        return color.opacity(0.08)
    }

    private func cardBorderColor(for routineExercise: RoutineExercise) -> Color {
        guard let color = supersetColor(for: routineExercise) else { return Color.white.opacity(0.06) }
        return color.opacity(0.3)
    }

    // MARK: - Body

    private var sortedExercises: [RoutineExercise] {
        routine.routineExercisesList.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            // ScrollView + LazyVStack (not List): List snaps intra-row height
            // changes, making card/set expansion look like a re-render. A
            // LazyVStack interpolates height, so expansion reads as growth.
            // Drag-reorder (previously List.onMove) is reimplemented per-card
            // via ExerciseReorder in edit mode.
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    topBar
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if supersetEditMode == nil && !isEditMode {
                        RoutineScheduleCard(
                            schedule: routine.schedule,
                            nextDue: viewModel.nextDueDate(for: routine),
                            onTap: {
                                HapticManager.shared.light()
                                showingSchedulePlanner = true
                            }
                        )
                        .padding(.bottom, 10)
                    }

                    if routine.routineExercisesList.isEmpty {
                        ContentUnavailableView {
                            Label("routine.empty.title".localized, systemImage: "dumbbell")
                        } description: {
                            Text("routine.empty.description".localized)
                        } actions: {
                            Button("routine.add_exercise".localized) {
                                showingAddExercise = true
                            }
                            .buttonStyle(.onyxProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        exerciseRows
                    }

                    if !routine.routineExercisesList.isEmpty && supersetEditMode == nil {
                        DashedCreateButton(title: "routine.add_exercise".localized) {
                            showingAddExercise = true
                        }
                        .padding(.top, 6)
                    }

                    Color.clear
                        .frame(height: 40)
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: scrollToExerciseId) { _, newValue in
                guard let id = newValue else { return }
                withAnimation(DesignSystem.Animation.spring) {
                    proxy.scrollTo(id, anchor: .top)
                }
                scrollToExerciseId = nil
            }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomInset
        }
        .overlay(alignment: .top) {
            reorderHintOverlay
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToRoutineView(routine: routine, viewModel: viewModel, exercisesViewModel: exercisesViewModel)
        }
        .sheet(isPresented: $showingSchedulePlanner) {
            SchedulePlanningSheet(routine: routine, viewModel: viewModel)
        }
        .sheet(item: $addAlternativeTarget) { target in
            AddAlternativeView(
                routineExercise: target,
                viewModel: viewModel,
                // Expand the new alternative's inline set editor so its reps and
                // weight can be defined right away
                onAdded: { focusedAlternativeId = $0.id }
            )
        }
        .sheet(item: $browseAlternativesTarget, onDismiss: applyPendingBrowseAction) { target in
            AlternativesBrowseView(
                routineExercise: target,
                onSelect: { alternative in
                    // Defer the actual expand/scroll until this sheet has fully
                    // dismissed (see applyPendingBrowseAction) to avoid the
                    // dismiss/transition race documented in alternative-exercises.md.
                    pendingExpandExerciseId = target.id
                    pendingExpandAlternativeId = alternative.id
                },
                onAdd: {
                    // A sheet cannot present while another dismisses — hand off via
                    // onDismiss instead of presenting AddAlternativeView directly.
                    pendingAddTarget = target
                }
            )
        }
        .sheet(item: $selectedExerciseForOverload) { exercise in
            WeightIncreaseSheet(
                routineExercise: exercise,
                onApply: { increment in
                    viewModel.applyProgressiveOverload(for: exercise, weightIncrement: increment)
                    selectedExerciseForOverload = nil
                    overloadBannerDismissedForExercise[exercise.id] = true
                },
                onCancel: {
                    selectedExerciseForOverload = nil
                }
            )
        }
        .alert("routine.rename".localized, isPresented: $showingRenameAlert) {
            TextField("add_routine.name_placeholder".localized, text: $renameText)
            Button("action.save".localized) {
                let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty && trimmedName != routine.name {
                    routine.name = trimmedName
                    viewModel.updateRoutine(routine)
                }
            }
            Button("action.cancel".localized, role: .cancel) {}
        }
        .alert("routine.delete".localized, isPresented: $showingDeleteAlert) {
            Button("action.delete".localized, role: .destructive) {
                viewModel.deleteRoutine(routine)
                dismiss()
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("routine.delete.confirm".localized)
        }
        .alert("routine_exercise.delete.title".localized, isPresented: $showingDeleteExerciseAlert) {
            Button("action.delete".localized, role: .destructive) {
                if let exercise = exercisePendingDeletion {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeRoutineExercise(exercise, from: routine)
                    }
                }
                exercisePendingDeletion = nil
            }
            Button("action.cancel".localized, role: .cancel) {
                exercisePendingDeletion = nil
            }
        } message: {
            if let exercise = exercisePendingDeletion {
                Text("routine_exercise.delete.message".localized(exercise.exercise?.name ?? ""))
            }
        }
        .fullScreenCover(isPresented: $showingActiveWorkout) {
            ActiveWorkoutView(viewModel: workoutViewModel, exercisesViewModel: exercisesViewModel)
        }
    }

    // MARK: - Top bar & title

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                HapticManager.shared.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.back".localized)

            Spacer()

            if supersetEditMode == nil && !routine.routineExercisesList.isEmpty {
                Button {
                    toggleEditMode()
                } label: {
                    Text(isEditMode ? "action.done".localized : "action.edit".localized)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(isEditMode ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.tint)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(isEditMode ? DesignSystem.Colors.tint : DesignSystem.Colors.tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if supersetEditMode == nil {
                Menu {
                    Button {
                        renameText = routine.name
                        showingRenameAlert = true
                    } label: {
                        Label("routine.rename".localized, systemImage: "pencil")
                    }
                    Button {
                        HapticManager.shared.success()
                        viewModel.duplicateRoutine(routine)
                    } label: {
                        Label("routine.duplicate".localized, systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("routine.delete".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routine.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RoutineMetricsService.primaryMuscleGroups(for: routine), id: \.self) { muscle in
                        MuscleChipView(muscleGroup: muscle)
                    }
                    Text(metaText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.leading, 4)
                }
            }

            if let editMode = supersetEditMode {
                Text(editMode == .creating ? "superset.create_new".localized : "superset.edit".localized)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 10)
    }

    private var metaText: String {
        String(
            format: "routines.card_meta".localized,
            routine.routineExercisesList.count,
            RoutineMetricsService.totalSets(for: routine),
            RoutineMetricsService.estimatedDurationMinutes(for: routine)
        )
    }

    // MARK: - Exercise rows

    private var exerciseRows: some View {
        ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
            exerciseRow(index: index, routineExercise: routineExercise)
                // Scroll anchor for the alternatives-browse jump (scrollTo(exerciseId)).
                .id(routineExercise.id)
        }
    }

    @ViewBuilder
    private func exerciseRow(index: Int, routineExercise: RoutineExercise) -> some View {
        if supersetEditMode != nil {
            supersetSelectionCard(routineExercise)
                .padding(.vertical, 4)
        } else if isEditMode {
            editExerciseCard(routineExercise)
                .padding(.vertical, 4)
                .modifier(WiggleModifier(isWiggling: isEditMode))
                .scaleEffect(isEditMode ? 0.98 : 1.0)
                .animation(DesignSystem.Animation.spring, value: isEditMode)
                .exerciseReorderable(
                    routineExercise,
                    exercises: sortedExercises,
                    draggingId: $draggingId,
                    onReorder: persistReorder
                )
        } else {
            normalExerciseCard(routineExercise)
                .padding(.vertical, 4)

            // Link button between this exercise and the next
            if index < sortedExercises.count - 1,
               shouldShowLinkButton(between: routineExercise, and: sortedExercises[index + 1]) {
                SupersetLinkButton {
                    linkExercises(routineExercise, sortedExercises[index + 1])
                }
            }
        }
    }

    /// Superset edit mode: selection card.
    private func supersetSelectionCard(_ routineExercise: RoutineExercise) -> some View {
        let isSelected = supersetEditSelection.contains(routineExercise.id)
        return supersetEditRow(for: routineExercise)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(supersetEditRowBackground(for: routineExercise))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.tint.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Edit mode: delete + drag card.
    private func editExerciseCard(_ routineExercise: RoutineExercise) -> some View {
        editModeRow(for: routineExercise)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardBackgroundColor(for: routineExercise))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardBorderColor(for: routineExercise), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// One exercise as a self-contained card: header, info chips, expandable body.
    private func normalExerciseCard(_ routineExercise: RoutineExercise) -> some View {
        let isExerciseExpanded = expandedExerciseId == routineExercise.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                // Prevent collapse during set reorder mode
                guard setEditExerciseId != routineExercise.id else { return }
                withAnimation(DesignSystem.Animation.spring) {
                    // Expanding/collapsing via the header always lands on the
                    // primary variant (alternatives are opted into via the switcher).
                    focusedAlternativeId = nil
                    if isExerciseExpanded {
                        expandedExerciseId = nil
                        expandedSetId = nil
                    } else {
                        expandedExerciseId = routineExercise.id
                        expandedSetId = nil
                    }
                }
            } label: {
                let info = supersetInfo(for: routineExercise)
                let linePos = supersetLinePosition(for: routineExercise)
                let color = supersetColor(for: routineExercise)
                HStack(spacing: 10) {
                    ExerciseHeaderView(
                        routineExercise: routineExercise,
                        isEditMode: false,
                        supersetPosition: info?.position,
                        supersetTotal: info?.total,
                        supersetColor: color,
                        supersetLinePosition: linePos,
                        onSupersetAction: routine.routineExercisesList.count >= 2 ? {
                            if let supersetId = routineExercise.supersetId {
                                enterSupersetEdit(for: supersetId)
                            } else {
                                enterSupersetCreate(initiatingExercise: routineExercise)
                            }
                        } : nil,
                        onEditSets: {
                            enterSetEditMode(for: routineExercise)
                        },
                        onEditAlternatives: {
                            openAlternatives(for: routineExercise)
                        }
                    )

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .rotationEffect(.degrees(isExerciseExpanded ? 180 : 0))
                        .animation(DesignSystem.Animation.spring, value: isExerciseExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: expandedExerciseId)

            // Info chips strip (always visible)
            infoChips(for: routineExercise)
                .padding(.top, 10)

            if isExerciseExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.top, 12)

                    if setEditExerciseId == routineExercise.id {
                        setEditContent(for: routineExercise)
                    } else {
                        normalSetContent(for: routineExercise)
                    }
                }
                // Reveal the body as the card grows in height (fluid in LazyVStack,
                // unlike List's row-height snap). Clipped by the card's .clipShape.
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackgroundColor(for: routineExercise))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorderColor(for: routineExercise), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            supersetContextMenu(for: routineExercise)
        }
    }

    @ViewBuilder
    private func infoChips(for routineExercise: RoutineExercise) -> some View {
        let pause = routineExercise.isInSuperset
            ? supersetRestTime(for: routineExercise)
            : restTime(for: routineExercise)

        HStack(spacing: 6) {
            MetaChipView(
                icon: "timer",
                text: String(format: "routine.chip.pause".localized, TimeFormatting.formatRestTime(pause)),
                color: DesignSystem.Colors.tint
            )

            if let min = routineExercise.targetRepMin, let max = routineExercise.targetRepMax {
                MetaChipView(
                    icon: "target",
                    text: String(format: "routine.chip.goal".localized, min, max)
                )
            }

            if routineExercise.hasAlternatives {
                Button {
                    HapticManager.shared.light()
                    browseAlternativesTarget = routineExercise
                } label: {
                    MetaChipView(
                        icon: "arrow.triangle.2.circlepath",
                        text: "alternatives.count".localized(routineExercise.alternativesList.count)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("alternatives.browse.title".localized)
                .accessibilityHint("alternatives.browse.hint".localized)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom inset (CTA / superset toolbar)

    @ViewBuilder
    private var bottomInset: some View {
        if supersetEditMode != nil {
            // Superset edit toolbar
            HStack {
                Button("action.cancel".localized) {
                    cancelSupersetEdit()
                }
                .foregroundStyle(Color.white.opacity(0.6))

                Spacer()

                Text("superset.selected_count".localized(supersetEditSelection.count))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))

                Spacer()

                Button("action.done".localized) {
                    applySupersetEdit()
                }
                .fontWeight(.semibold)
                .foregroundStyle(canApplySupersetEdit ? DesignSystem.Colors.tint : Color.white.opacity(0.4))
                .disabled(!canApplySupersetEdit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DesignSystem.Colors.card)
            .overlay(alignment: .top) {
                Divider().overlay(Color.white.opacity(0.08))
            }
        } else if !routine.routineExercisesList.isEmpty && !isEditMode {
            // Start Workout CTA
            Button {
                HapticManager.shared.medium()
                workoutViewModel.startWorkout(routine: routine)
                showingActiveWorkout = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("routine.start_workout".localized)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(DesignSystem.Colors.tint)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: DesignSystem.Colors.tint.opacity(0.35), radius: 15, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.85), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - Reorder hint

    @ViewBuilder
    private var reorderHintOverlay: some View {
        if showReorderHint {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.textOnTint)

                Text("routine.drag_to_reorder".localized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)

                Spacer()

                Button {
                    withAnimation(DesignSystem.Animation.spring) {
                        showReorderHint = false
                        hasSeenReorderHint = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.textOnTint.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignSystem.Colors.tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Auto-dismiss after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(DesignSystem.Animation.spring) {
                        showReorderHint = false
                        hasSeenReorderHint = true
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleEditMode() {
        // Clear any dangling drag state (e.g. a drag dropped in the gutter never
        // reaches a card's performDrop, which would otherwise leave it dimmed).
        draggingId = nil
        withAnimation(DesignSystem.Animation.spring) {
            if isEditMode {
                // Dismiss keyboard
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                // Announce edit mode exit
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Editing complete."
                )
            } else {
                // Collapse any expanded exercises when entering edit mode
                expandedExerciseId = nil
                expandedSetId = nil
                setEditExerciseId = nil
                focusedAlternativeId = nil

                // Announce to VoiceOver users
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "routine.edit_mode_announcement".localized
                )

                // Show hint for first-time users
                if !hasSeenReorderHint && routine.routineExercisesList.count > 1 {
                    // Delay to let wiggle animation start first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(DesignSystem.Animation.spring) {
                            showReorderHint = true
                        }
                    }
                }
            }
            isEditMode.toggle()
        }
    }

    /// Persist a drag-reordered exercise list (from ExerciseReorder's drop
    /// delegate): reassign `order` to match the new sequence and save.
    private func persistReorder(_ ordered: [RoutineExercise]) {
        for (index, exercise) in ordered.enumerated() {
            exercise.order = index
        }
        viewModel.updateRoutine(routine)
    }

    private func saveCurrentExpandedSet() {
        guard let currentExpandedId = expandedSetId,
              let currentExercise = currentRoutineExercise,
              let currentSet = currentExercise.setsList.first(where: { $0.id == currentExpandedId }) else { return }
        if currentSet.reps != editingReps || currentSet.weight != editingWeight {
            currentSet.reps = editingReps
            currentSet.weight = editingWeight
            viewModel.updateSet(currentSet)
        }
    }

    private func updateSet(_ set: ExerciseSet, reps: Int? = nil, weight: Double? = nil) {
        if let reps = reps {
            set.reps = reps
        }
        if let weight = weight {
            set.weight = weight
        }
        viewModel.updateSet(set)
    }

    private func updateAllSetsRestTime(for routineExercise: RoutineExercise, restTime: TimeInterval) {
        for set in routineExercise.setsList {
            set.restTime = restTime
            viewModel.updateSet(set)
        }
    }

    private func handleSetUpdate(
        set: ExerciseSet,
        reps: Int?,
        weight: Double?,
        routineExercise: RoutineExercise,
        applyToAll: Bool
    ) {
        if applyToAll {
            // Apply to all sets in this exercise
            for exerciseSet in routineExercise.setsList {
                if let reps = reps {
                    exerciseSet.reps = reps
                }
                if let weight = weight {
                    exerciseSet.weight = weight
                }
                viewModel.updateSet(exerciseSet)
            }
        } else {
            // Apply only to current set
            updateSet(set, reps: reps, weight: weight)
        }
    }

    private func handleApplyRepsToAll(reps: Int, routineExercise: RoutineExercise) {
        for exerciseSet in routineExercise.setsList {
            exerciseSet.reps = reps
            viewModel.updateSet(exerciseSet)
        }
    }

    private func handleApplyWeightToAll(weight: Double, routineExercise: RoutineExercise) {
        for exerciseSet in routineExercise.setsList {
            exerciseSet.weight = weight
            viewModel.updateSet(exerciseSet)
        }
    }
}

#Preview {
    Text("RoutineDetailView Preview")
}
