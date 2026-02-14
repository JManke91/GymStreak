import SwiftUI

struct RoutineDetailView: View {
    @Bindable var routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @State private var showingAddExercise = false
    @State private var showingDeleteAlert = false
    @State private var showingDeleteExerciseAlert = false
    @State private var exercisePendingDeletion: RoutineExercise?
    @State private var showingActiveWorkout = false
    @State private var editingRoutineName: String = ""
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
    @AppStorage("hasSeenReorderHint") private var hasSeenReorderHint = false
    @AppStorage("hasSeenSupersetHint") private var hasSeenSupersetHint = false
    @State private var showReorderHint = false
    @State private var showSupersetHint = false

    // Superset selection mode (independent of edit mode)
    @State private var isSupersetSelectionMode = false
    @State private var selectedForSuperset: Set<UUID> = []

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

    // Helper for selection icon in superset selection mode
    private func selectionIcon(for exercise: RoutineExercise) -> String {
        if selectedForSuperset.contains(exercise.id) {
            return "checkmark.circle.fill"
        } else {
            return "circle"
        }
    }

    // Helper for selection color in superset selection mode
    private func selectionColor(for exercise: RoutineExercise) -> Color {
        if selectedForSuperset.contains(exercise.id) {
            return DesignSystem.Colors.tint
        } else {
            return .secondary
        }
    }

    // Check if all selected exercises are already in the same superset
    private var allSelectedInSameSuperset: Bool {
        let selectedExercises = routine.routineExercisesList.filter { selectedForSuperset.contains($0.id) }
        let supersetIds = Set(selectedExercises.compactMap(\.supersetId))
        let hasStandaloneSelections = selectedExercises.contains { $0.supersetId == nil }

        // If all selected are from the same superset and no standalone exercises
        return supersetIds.count == 1 && !hasStandaloneSelections
    }

    // Check if there are exercises that will be removed from superset (unselected superset exercises)
    private var canUpdateSuperset: Bool {
        !exercisesToRemoveFromSuperset.isEmpty
    }

    // Determine the action type for the superset button
    private enum SupersetAction {
        case createSuperset       // Create new superset from standalone exercises
        case updateSuperset       // Keep selected exercises in superset (remove unselected)
        case linkExercises        // Add standalone exercises to existing superset
        case mergeSuperset        // Merge multiple supersets together
        case noAction
    }

    // Get exercises that would be removed (in superset but not selected)
    private var exercisesToRemoveFromSuperset: [RoutineExercise] {
        routine.routineExercisesList.filter { $0.isInSuperset && !selectedForSuperset.contains($0.id) }
    }

    private var currentSupersetAction: SupersetAction {
        let selectedExercises = routine.routineExercisesList.filter { selectedForSuperset.contains($0.id) }
        let supersetIds = Set(selectedExercises.compactMap(\.supersetId))
        let hasStandaloneSelections = selectedExercises.contains { $0.supersetId == nil }
        let hasUnselectedSupersetExercises = !exercisesToRemoveFromSuperset.isEmpty

        // If there are unselected superset exercises, we're updating (removing the unselected)
        // Allow this even if only 1 exercise remains selected (superset will auto-dissolve)
        if hasUnselectedSupersetExercises {
            return .updateSuperset
        }
        // Multiple supersets selected - offer to merge
        if supersetIds.count > 1 && !hasStandaloneSelections {
            return .mergeSuperset
        }
        // Only standalone exercises - create new superset
        if hasStandaloneSelections && supersetIds.isEmpty && selectedExercises.count >= 2 {
            return .createSuperset
        }
        // Mix of standalone and superset exercises - link them together
        if hasStandaloneSelections && !supersetIds.isEmpty && selectedExercises.count >= 2 {
            return .linkExercises
        }

        return .noAction
    }

    // Determine the label for the superset action button
    private var supersetActionLabel: String {
        let removeCount = exercisesToRemoveFromSuperset.count
        switch currentSupersetAction {
        case .updateSuperset:
            if removeCount == 1 {
                return "superset.remove_one".localized
            } else {
                return "superset.remove_multiple".localized(removeCount)
            }
        case .mergeSuperset:
            return "superset.merge".localized(selectedForSuperset.count)
        case .createSuperset:
            return "superset.create".localized(selectedForSuperset.count)
        case .linkExercises:
            return "superset.link_count".localized(selectedForSuperset.count)
        case .noAction:
            return "superset.select_exercises".localized
        }
    }

    // Perform the superset action
    private func performSupersetAction() {
        let selectedExercises = routine.routineExercisesList.filter { selectedForSuperset.contains($0.id) }

        switch currentSupersetAction {
        case .updateSuperset:
            // Remove UNSELECTED exercises from their supersets
            for exercise in exercisesToRemoveFromSuperset {
                viewModel.removeExerciseFromSuperset(exercise, in: routine)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .createSuperset, .linkExercises, .mergeSuperset:
            // Create/merge superset from selected exercises
            viewModel.createSuperset(from: selectedExercises, in: routine)
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .noAction:
            break
        }

        isSupersetSelectionMode = false
        selectedForSuperset.removeAll()
    }

    // Enter superset selection mode with appropriate pre-selection
    private func enterSupersetSelectionMode(preselectedExerciseId: UUID? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isSupersetSelectionMode = true
            // Collapse any expanded exercises
            expandedExerciseId = nil
            expandedSetId = nil

            // Pre-select exercises based on context
            if let preselectedId = preselectedExerciseId {
                // Coming from context menu - pre-select this exercise
                selectedForSuperset = [preselectedId]
            } else {
                // Coming from toolbar - pre-select all exercises that are in supersets
                let supersetExerciseIds = routine.routineExercisesList
                    .filter { $0.isInSuperset }
                    .map { $0.id }
                selectedForSuperset = Set(supersetExerciseIds)
            }

            // Show hint for first-time users (only if no pre-selection)
            if !hasSeenSupersetHint && selectedForSuperset.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showSupersetHint = true
                    }
                }
            }
        }
    }

    // MARK: - Superset Selection Mode Row View Builder
    @ViewBuilder
    private func supersetSelectionRow(for routineExercise: RoutineExercise) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if selectedForSuperset.contains(routineExercise.id) {
                    selectedForSuperset.remove(routineExercise.id)
                } else {
                    selectedForSuperset.insert(routineExercise.id)
                }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: selectionIcon(for: routineExercise))
                    .font(.title2)
                    .foregroundStyle(selectionColor(for: routineExercise))

                // Exercise header with superset info
                let info = supersetInfo(for: routineExercise)
                let linePos = supersetLinePosition(for: routineExercise)
                ExerciseHeaderView(
                    routineExercise: routineExercise,
                    isEditMode: true,
                    showDragHandle: false,
                    supersetPosition: info?.position,
                    supersetTotal: info?.total,
                    supersetLinePosition: linePos
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            ExerciseHeaderView(
                routineExercise: routineExercise,
                isEditMode: true,
                supersetPosition: info?.position,
                supersetTotal: info?.total,
                supersetLinePosition: linePos
            )
        }
    }

    // Superset selection mode row background color (indicator is now in row content)
    private func supersetSelectionRowBackgroundColor(for routineExercise: RoutineExercise) -> Color {
        if selectedForSuperset.contains(routineExercise.id) {
            return DesignSystem.Colors.tint.opacity(0.15)
        } else if routineExercise.isInSuperset {
            return DesignSystem.Colors.tint.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    // Edit mode row background color (indicator is now in row content)
    private func editModeRowBackgroundColor(for routineExercise: RoutineExercise) -> Color {
        routineExercise.isInSuperset ? DesignSystem.Colors.tint.opacity(0.08) : Color.clear
    }

    // Normal mode row background color (indicator is now in row content)
    private func normalModeRowBackgroundColor(for routineExercise: RoutineExercise) -> Color {
        routineExercise.isInSuperset ? DesignSystem.Colors.tint.opacity(0.08) : Color.clear
    }

    var body: some View {
        List {
            Section {
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
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(routine.routineExercisesList.sorted(by: { $0.order < $1.order })) { routineExercise in
                        Group {
                            if isSupersetSelectionMode {
                                // Superset selection mode (indicator now in row content via ExerciseHeaderView)
                                supersetSelectionRow(for: routineExercise)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowBackground(supersetSelectionRowBackgroundColor(for: routineExercise))
                                    .listRowSeparator(routineExercise.isInSuperset ? .hidden : .automatic)
                            } else if isEditMode {
                                // Edit mode (indicator now in row content via ExerciseHeaderView)
                                editModeRow(for: routineExercise)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowBackground(editModeRowBackgroundColor(for: routineExercise))
                                    .listRowSeparator(routineExercise.isInSuperset ? .hidden : .automatic)
                            } else {
                                // Normal mode: Full disclosure group
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedExerciseId == routineExercise.id },
                                        set: { isExpanded in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if isExpanded {
                                                    expandedExerciseId = routineExercise.id
                                                    expandedSetId = nil
                                                } else {
                                                    expandedExerciseId = nil
                                                    expandedSetId = nil
                                                }
                                            }
                                        }
                                    )
                                ) {
                            // Sets content
                            VStack(spacing: 12) {
                                // Rest Timer Configuration
                                // For superset exercises: show SupersetRestTimerConfig only for the first exercise
                                // For standalone exercises: show regular RestTimerConfigView
                                if routineExercise.isInSuperset {
                                    if isFirstInSuperset(routineExercise) {
                                        // Show superset rest timer config for the first exercise in the superset
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
                                    // Other superset exercises don't show rest timer config
                                } else {
                                    // Standalone exercise - show regular config
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
                                        onTap: {
                                            withAnimation(.snappy(duration: 0.35)) {
                                                if expandedSetId == set.id {
                                                    // Save before collapsing
                                                    saveCurrentExpandedSet()
                                                    expandedSetId = nil
                                                    currentRoutineExercise = nil
                                                } else {
                                                    // Save currently expanded set before switching
                                                    saveCurrentExpandedSet()
                                                    expandedSetId = set.id
                                                    editingReps = set.reps
                                                    editingWeight = set.weight
                                                    initialReps = set.reps
                                                    initialWeight = set.weight
                                                    currentRoutineExercise = routineExercise
                                                    // Reset banner dismissed states when opening a new set
                                                    repsBannerDismissedForExercise[routineExercise.id] = false
                                                    weightBannerDismissedForExercise[routineExercise.id] = false
                                                }
                                            }
                                        },
                                        onUpdate: { reps, weight in
                                            // Guard: only process updates for the currently expanded set.
                                            // During animated set transitions, the old set's onChange handlers
                                            // can fire with the new set's values, overwriting the old set's data.
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
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                handleApplyRepsToAll(
                                                    reps: editingReps,
                                                    routineExercise: routineExercise
                                                )
                                                repsBannerDismissedForExercise[routineExercise.id] = true
                                                initialReps = editingReps
                                            }
                                        },
                                        onApplyWeightToAll: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                handleApplyWeightToAll(
                                                    weight: editingWeight,
                                                    routineExercise: routineExercise
                                                )
                                                weightBannerDismissedForExercise[routineExercise.id] = true
                                                initialWeight = editingWeight
                                            }
                                        },
                                        onDismissRepsBanner: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                repsBannerDismissedForExercise[routineExercise.id] = true
                                            }
                                        },
                                        onDismissWeightBanner: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                weightBannerDismissedForExercise[routineExercise.id] = true
                                            }
                                        },
                                        onDelete: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                viewModel.removeSet(set, from: routineExercise)
                                                // Clear expanded state if we deleted the expanded set
                                                if expandedSetId == set.id {
                                                    expandedSetId = nil
                                                }
                                            }
                                        }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity.combined(with: .move(edge: .leading))
                                    ))
                                }

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.addSet(to: routineExercise)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("exercise.add_set".localized)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(DesignSystem.Colors.tint)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(DesignSystem.Colors.input)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)

                                } label: {
                                    let info = supersetInfo(for: routineExercise)
                                    let linePos = supersetLinePosition(for: routineExercise)
                                    ExerciseHeaderView(
                                        routineExercise: routineExercise,
                                        isEditMode: false,
                                        supersetPosition: info?.position,
                                        supersetTotal: info?.total,
                                        supersetLinePosition: linePos
                                    )
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .listRowBackground(normalModeRowBackgroundColor(for: routineExercise))
                                .listRowSeparator(routineExercise.isInSuperset ? .hidden : .automatic)
                                .sensoryFeedback(.selection, trigger: expandedExerciseId)
                                // Only allow deleting exercise when collapsed
                                .deleteDisabled(expandedExerciseId == routineExercise.id)
                                // Context menu for superset management
                                .contextMenu {
                                    if routineExercise.isInSuperset {
                                        Button {
                                            viewModel.removeExerciseFromSuperset(routineExercise, in: routine)
                                        } label: {
                                            Label("superset.remove_from".localized, systemImage: "link.badge.minus")
                                        }

                                        if let supersetId = routineExercise.supersetId {
                                            Button(role: .destructive) {
                                                viewModel.dissolveSuperset(supersetId, in: routine)
                                            } label: {
                                                Label("superset.dissolve".localized, systemImage: "link.badge.xmark")
                                            }
                                        }

                                        Divider()
                                    }

                                    if routine.routineExercisesList.count >= 2 {
                                        Button {
                                            enterSupersetSelectionMode(preselectedExerciseId: routineExercise.id)
                                        } label: {
                                            Label(
                                                routineExercise.isInSuperset ? "superset.modify".localized : "superset.create_menu".localized,
                                                systemImage: "link.badge.plus"
                                            )
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        exercisePendingDeletion = routineExercise
                                        showingDeleteExerciseAlert = true
                                    } label: {
                                        Label("exercise.delete".localized, systemImage: "trash")
                                    }
                                }
                            }
                        }
                        // Edit mode visual effects
                        .modifier(WiggleModifier(isWiggling: isEditMode))
                        .scaleEffect(isEditMode ? 0.98 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEditMode)
                    }
                    .onMove(perform: isEditMode ? moveRoutineExercises : nil)
                }

                if !routine.routineExercisesList.isEmpty {
                    Button {
                        showingAddExercise = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title3)
                                .foregroundStyle(DesignSystem.Colors.textOnTint)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(DesignSystem.Colors.tint))

                            Text("routine.add_exercise".localized)
                                .font(.body.weight(.semibold))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } header: {
                HStack {
                    Text("routine.exercises".localized)
                    Spacer()
                    // Only show Edit button when not in superset selection mode
                    if !routine.routineExercisesList.isEmpty && !isSupersetSelectionMode {
                        Button(isEditMode ? "action.done".localized : "action.edit".localized) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if isEditMode {
                                    // Dismiss keyboard
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                                    // Exiting edit mode - save routine name if changed
                                    let trimmedName = editingRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmedName.isEmpty && trimmedName != routine.name {
                                        routine.name = trimmedName
                                        routine.updatedAt = Date()
                                        viewModel.updateRoutine(routine)
                                    }

                                    // Announce edit mode exit
                                    UIAccessibility.post(
                                        notification: .announcement,
                                        argument: "Editing complete."
                                    )
                                } else {
                                    // Entering edit mode
                                    editingRoutineName = routine.name

                                    // Collapse any expanded exercises when entering edit mode
                                    expandedExerciseId = nil
                                    expandedSetId = nil

                                    // Announce to VoiceOver users
                                    UIAccessibility.post(
                                        notification: .announcement,
                                        argument: "routine.edit_mode_announcement".localized
                                    )

                                    // Show hint for first-time users
                                    if !hasSeenReorderHint && routine.routineExercisesList.count > 1 {
                                        // Delay to let wiggle animation start first
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                showReorderHint = true
                                            }
                                        }
                                    }
                                }
                                isEditMode.toggle()
                            }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isEditMode ? .orange : DesignSystem.Colors.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isEditMode ? Color.orange.opacity(0.1) : DesignSystem.Colors.tint.opacity(0.1))
                        )
                    }
                }
                .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isSupersetSelectionMode ? "superset.link_exercises".localized : (isEditMode ? "" : routine.name))
        .navigationBarTitleDisplayMode(isSupersetSelectionMode || isEditMode ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                EditableRoutineTitleView(name: $editingRoutineName)
                    .opacity(isEditMode && !isSupersetSelectionMode ? 1 : 0)
                    .allowsHitTesting(isEditMode && !isSupersetSelectionMode)
                    .animation(.none, value: isEditMode)
            }
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
            // Show action button when valid action is available
            if isSupersetSelectionMode && currentSupersetAction != .noAction {
                // Superset action button
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        performSupersetAction()
                    } label: {
                        Text(supersetActionLabel)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(currentSupersetAction == .updateSuperset
                        ? .onyxProminent(backgroundColor: .orange, foregroundColor: .white)
                        : .onyxProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.card)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !routine.routineExercisesList.isEmpty && !isEditMode && !isSupersetSelectionMode {
                // Start Workout button (only in normal mode)
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        workoutViewModel.startWorkout(routine: routine)
                        showingActiveWorkout = true
                    } label: {
                        Label("routine.start_workout".localized, systemImage: "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.onyxProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.card)
                }
            }
        }
        .toolbar {
            // Leading toolbar - Cancel button in superset selection mode
            ToolbarItem(placement: .navigationBarLeading) {
                if isSupersetSelectionMode {
                    Button("action.cancel".localized) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isSupersetSelectionMode = false
                            selectedForSuperset.removeAll()
                        }
                    }
                    .foregroundStyle(.red)
                }
            }

            // Trailing toolbar - action button or link button
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSupersetSelectionMode {
                    // Done/action button in selection mode
                    Button {
                        performSupersetAction()
                    } label: {
                        Text(currentSupersetAction == .updateSuperset ? "superset.remove".localized : "superset.link".localized)
                            .fontWeight(.semibold)
                    }
                    .disabled(currentSupersetAction == .noAction)
                } else if !isEditMode && routine.routineExercisesList.count >= 2 {
                    // Link button - visible when 2+ exercises and not in edit mode
                    Button {
                        enterSupersetSelectionMode()
                    } label: {
                        Image(systemName: "link.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("superset.link_accessibility".localized)
                }
            }

            // Additional trailing toolbar - delete button (only when not in selection mode or edit mode)
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isSupersetSelectionMode && !isEditMode {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if showReorderHint {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.draw")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.textOnTint)

                        Text("routine.drag_to_reorder".localized)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DesignSystem.Colors.textOnTint)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // Auto-dismiss after 4 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showReorderHint = false
                            hasSeenReorderHint = true
                        }
                    }
                }
            }

            // Superset selection hint
            if showSupersetHint {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.textOnTint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("superset.hint_title".localized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignSystem.Colors.textOnTint)
                            Text("superset.hint_description".localized)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.textOnTint.opacity(0.85))
                        }

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSupersetHint = false
                                hasSeenSupersetHint = true
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // Auto-dismiss after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showSupersetHint = false
                            hasSeenSupersetHint = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToRoutineView(routine: routine, viewModel: viewModel, exercisesViewModel: exercisesViewModel)
        }
        .alert("routine.delete".localized, isPresented: $showingDeleteAlert) {
            Button("action.delete".localized, role: .destructive) {
                viewModel.deleteRoutine(routine)
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("routine.delete.confirm".localized)
        }
        .alert("routine_exercise.delete.title".localized, isPresented: $showingDeleteExerciseAlert) {
            Button("action.delete".localized, role: .destructive) {
                if let exercise = exercisePendingDeletion {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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

    private func deleteRoutineExercises(offsets: IndexSet) {
        for index in offsets {
            let routineExercise = routine.routineExercisesList.sorted(by: { $0.order < $1.order })[index]
            viewModel.removeRoutineExercise(routineExercise, from: routine)
        }
    }

    private func moveRoutineExercises(from source: IndexSet, to destination: Int) {
        // Provide haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Get sorted exercises
        var sortedExercises = routine.routineExercisesList.sorted(by: { $0.order < $1.order })

        // Move items
        sortedExercises.move(fromOffsets: source, toOffset: destination)

        // Update order property for all exercises
        for (index, exercise) in sortedExercises.enumerated() {
            exercise.order = index
        }

        // Save changes
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

// MARK: - Supporting Views

struct EditableRoutineTitleView: View {
    @Binding var name: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("add_routine.name_placeholder".localized, text: $name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("routine.name_accessibility".localized)
                .accessibilityHint("routine.name_edit_hint".localized)

            // Make the pencil icon tappable
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(.orange)
                .contentTransition(.identity)
                .onTapGesture {
                    isFocused = true
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            // Invisible tap catcher for padding areas
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
        }
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.6))
                .frame(height: 2)
        }
        .frame(maxWidth: 200)
    }
}

struct ExerciseHeaderView: View {
    let routineExercise: RoutineExercise
    var isEditMode: Bool = false
    var showDragHandle: Bool = true
    var supersetPosition: Int? = nil
    var supersetTotal: Int? = nil
    var supersetLinePosition: SupersetPosition? = nil

    // Fixed width for the superset indicator area - ensures consistent alignment for all exercises
    private let indicatorAreaWidth: CGFloat = 16
    private let indicatorTrailingSpacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            // FIXED-WIDTH superset indicator area (always present for consistent alignment)
            // For superset exercises: shows the line indicator
            // For standalone exercises: empty but reserves the same space
            ZStack {
                if let linePosition = supersetLinePosition {
                    SupersetLineIndicator(position: linePosition)
                }
            }
            .frame(width: indicatorAreaWidth)
            .padding(.trailing, indicatorTrailingSpacing)

            HStack(spacing: 12) {
                // Muscle group badge
                if let exercise = routineExercise.exercise {
                    MuscleGroupAbbreviationBadge(
                        muscleGroups: exercise.muscleGroups,
                        isActive: !isEditMode
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(routineExercise.exercise?.name ?? "Unknown")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)

                        if let exercise = routineExercise.exercise {
                            Image(systemName: exercise.equipmentType.icon)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Text("routine.sets_count".localized(routineExercise.setsList.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Superset position badge
                if let position = supersetPosition, let total = supersetTotal {
                    SupersetBadge(position: position, total: total)
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

struct RoutineSetRowView: View {
    let set: ExerciseSet
    let index: Int
    let isExpanded: Bool
    @Binding var editingReps: Int
    @Binding var editingWeight: Double
    let initialReps: Int
    let initialWeight: Double
    let hasMultipleSets: Bool
    let repsBannerDismissed: Bool
    let weightBannerDismissed: Bool
    let totalSets: Int
    let onTap: () -> Void
    let onUpdate: (Int, Double) -> Void
    let onApplyRepsToAll: () -> Void
    let onApplyWeightToAll: () -> Void
    let onDismissRepsBanner: () -> Void
    let onDismissWeightBanner: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteSetAlert = false

    // Computed property to check if reps have changed
    private var repsChanged: Bool {
        editingReps != initialReps
    }

    // Computed property to check if weight has changed
    private var weightChanged: Bool {
        editingWeight != initialWeight
    }

    private var backgroundColor: Color {
        if isExpanded {
            return DesignSystem.Colors.cardElevated
        } else {
            return Color.clear
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Set header
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            }) {
                HStack(spacing: 12) {
                    // Set number badge
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.textOnTint)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.tint)
                        .clipShape(Circle())

                    HStack(spacing: 8) {
                        Text("set.reps".localized(set.reps))
                        Text("×")
                            .foregroundStyle(.secondary)
                        Text("set.weight".localized(set.weight))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(isExpanded ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                        .foregroundStyle(isExpanded ? DesignSystem.Colors.tint : .secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("accessibility.set.label".localized(index + 1, set.reps, set.weight))
            .accessibilityHint(isExpanded ? "accessibility.set.hint.expanded".localized : "accessibility.set.hint.collapsed".localized)
            .accessibilityAddTraits(.isButton)

            // Expanded edit form
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(spacing: 16) {
                    // Reps input with contextual banner
                    VStack(spacing: 8) {
                        HorizontalStepper(
                            title: "set.reps_label".localized,
                            value: $editingReps,
                            range: 1...100,
                            step: 1
                        ) { newValue in
                            onUpdate(newValue, editingWeight)
                        }

                        // Reps Apply to All Banner
                        if hasMultipleSets && repsChanged && !repsBannerDismissed {
                            ApplyToAllBanner(
                                type: .reps,
                                setCount: totalSets,
                                onApply: onApplyRepsToAll,
                                onDismiss: onDismissRepsBanner
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                    }

                    // Weight input with contextual banner
                    VStack(spacing: 8) {
                        WeightInput(
                            title: "set.weight_label".localized,
                            weight: $editingWeight,
                            increment: 0.25
                        ) { newValue in
                            onUpdate(editingReps, newValue)
                        }

                        // Weight Apply to All Banner
                        if hasMultipleSets && weightChanged && !weightBannerDismissed {
                            ApplyToAllBanner(
                                type: .weight,
                                setCount: totalSets,
                                onApply: onApplyWeightToAll,
                                onDismiss: onDismissWeightBanner
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                    }

                    // Delete Set Button
                    Button(role: .destructive) {
                        showingDeleteSetAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                            Text("set.delete".localized)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isExpanded ? DesignSystem.Colors.tint.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .alert("set.delete.title".localized, isPresented: $showingDeleteSetAlert) {
            Button("set.delete.confirm".localized, role: .destructive) {
                onDelete()
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("set.delete.message".localized)
        }
    }
}

#Preview {
    Text("RoutineDetailView Preview")
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                wiggleCount = 0
            }
        }
    }
}
