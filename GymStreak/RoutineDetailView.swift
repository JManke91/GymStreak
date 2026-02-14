import SwiftUI

enum SupersetEditMode: Equatable {
    case editing(UUID)    // Editing existing superset (supersetId)
    case creating         // Creating new superset from scratch
}

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
    @State private var supersetEditMode: SupersetEditMode? = nil
    @State private var supersetEditSelection: Set<UUID> = []
    @AppStorage("hasSeenReorderHint") private var hasSeenReorderHint = false
    @State private var showReorderHint = false

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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            supersetEditMode = .editing(supersetId)
        }
    }

    /// Enter superset edit mode to create a new superset
    private func enterSupersetCreate(initiatingExercise: RoutineExercise) {
        supersetEditSelection = [initiatingExercise.id]
        expandedExerciseId = nil
        expandedSetId = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            supersetEditMode = .creating
        }
    }

    /// Toggle an exercise's membership in the superset selection
    private func toggleSupersetSelection(_ exercise: RoutineExercise) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
        switch supersetEditMode {
        case .creating:
            return supersetEditSelection.count >= 2
        case .editing:
            return true  // Always allow — 0 or 1 selected will dissolve/remove
        case .none:
            return false
        }
    }

    /// Apply superset edit changes on Done
    private func applySupersetEdit() {
        let selectedExercises = routine.routineExercisesList
            .filter { supersetEditSelection.contains($0.id) }
            .sorted { $0.order < $1.order }

        switch supersetEditMode {
        case .editing(let supersetId):
            if selectedExercises.count < 2 {
                // Dissolve the entire superset (0 or 1 remaining)
                viewModel.dissolveSuperset(supersetId, in: routine)
            } else {
                let currentMembers = Set(routine.routineExercisesList
                    .filter { $0.supersetId == supersetId }.map(\.id))
                let toAdd = supersetEditSelection.subtracting(currentMembers)
                let toRemove = currentMembers.subtracting(supersetEditSelection)

                for exercise in routine.routineExercisesList where toRemove.contains(exercise.id) {
                    viewModel.removeExerciseFromSuperset(exercise, in: routine)
                }
                for exercise in routine.routineExercisesList where toAdd.contains(exercise.id) {
                    viewModel.addExerciseToSuperset(exercise, supersetId: supersetId, in: routine)
                }
            }
        case .creating:
            guard selectedExercises.count >= 2 else { return }
            viewModel.createSuperset(from: selectedExercises, in: routine)
        case .none:
            break
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            supersetEditMode = nil
            supersetEditSelection = []
        }
    }

    /// Cancel superset edit mode
    private func cancelSupersetEdit() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            supersetEditMode = nil
            supersetEditSelection = []
        }
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

    /// Row background for superset edit mode
    private func supersetEditRowBackground(for exercise: RoutineExercise) -> Color {
        supersetEditSelection.contains(exercise.id) ? DesignSystem.Colors.tint.opacity(0.08) : .clear
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
            let letter = supersetLetter(for: routineExercise)
            let color = supersetColor(for: routineExercise)
            ExerciseHeaderView(
                routineExercise: routineExercise,
                isEditMode: true,
                supersetPosition: info?.position,
                supersetLetter: letter,
                supersetColor: color,
                supersetLinePosition: linePos
            )
        }
    }

    // Row background color using per-group superset color
    private func rowBackgroundColor(for routineExercise: RoutineExercise) -> Color {
        guard let color = supersetColor(for: routineExercise) else { return Color.clear }
        return color.opacity(0.08)
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
                    let sortedExercises = routine.routineExercisesList.sorted(by: { $0.order < $1.order })
                    ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                        Group {
                            if supersetEditMode != nil {
                                // Superset edit mode: selection row
                                supersetEditRow(for: routineExercise)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowBackground(supersetEditRowBackground(for: routineExercise))
                                    .listRowSeparator(.automatic)
                            } else if isEditMode {
                                // Edit mode (indicator now in row content via ExerciseHeaderView)
                                editModeRow(for: routineExercise)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowBackground(rowBackgroundColor(for: routineExercise))
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
                                    let letter = supersetLetter(for: routineExercise)
                                    let color = supersetColor(for: routineExercise)
                                    ExerciseHeaderView(
                                        routineExercise: routineExercise,
                                        isEditMode: false,
                                        supersetPosition: info?.position,
                                        supersetLetter: letter,
                                        supersetColor: color,
                                        supersetLinePosition: linePos,
                                        onSupersetAction: routine.routineExercisesList.count >= 2 ? {
                                            if let supersetId = routineExercise.supersetId {
                                                enterSupersetEdit(for: supersetId)
                                            } else {
                                                enterSupersetCreate(initiatingExercise: routineExercise)
                                            }
                                        } : nil
                                    )
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .listRowBackground(rowBackgroundColor(for: routineExercise))
                                .listRowSeparator(routineExercise.isInSuperset ? .hidden : .automatic)
                                .sensoryFeedback(.selection, trigger: expandedExerciseId)
                                // Only allow deleting exercise when collapsed
                                .deleteDisabled(expandedExerciseId == routineExercise.id)
                                // Context menu for superset management
                                .contextMenu {
                                    supersetContextMenu(for: routineExercise)
                                }

                                // Link button between this exercise and the next
                                if index < sortedExercises.count - 1,
                                   shouldShowLinkButton(between: routineExercise, and: sortedExercises[index + 1]) {
                                    SupersetLinkButton {
                                        linkExercises(routineExercise, sortedExercises[index + 1])
                                    }
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
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

                if !routine.routineExercisesList.isEmpty && supersetEditMode == nil {
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
                    if let editMode = supersetEditMode {
                        switch editMode {
                        case .editing(let supersetId):
                            let letter = supersetLabels[supersetId] ?? "?"
                            Text("superset.edit_named".localized(letter))
                        case .creating:
                            Text("superset.create_new".localized)
                        }
                    } else {
                        Text("routine.exercises".localized)
                    }
                    Spacer()
                    if !routine.routineExercisesList.isEmpty && supersetEditMode == nil {
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
        .navigationTitle(isEditMode ? "" : routine.name)
        .navigationBarTitleDisplayMode(isEditMode ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                EditableRoutineTitleView(name: $editingRoutineName)
                    .opacity(isEditMode ? 1 : 0)
                    .allowsHitTesting(isEditMode)
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
            if supersetEditMode != nil {
                // Superset edit toolbar
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Button("action.cancel".localized) {
                            cancelSupersetEdit()
                        }
                        .foregroundStyle(.secondary)

                        Spacer()

                        Text("superset.selected_count".localized(supersetEditSelection.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("action.done".localized) {
                            applySupersetEdit()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(canApplySupersetEdit ? DesignSystem.Colors.tint : .secondary)
                        .disabled(!canApplySupersetEdit)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.card)
                }
            } else if !routine.routineExercisesList.isEmpty && !isEditMode {
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
            // Trailing toolbar - delete button
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isEditMode && supersetEditMode == nil {
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
    var supersetLetter: String? = nil
    var supersetColor: Color? = nil
    var supersetLinePosition: SupersetPosition? = nil
    var onSupersetAction: (() -> Void)? = nil

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
                    SupersetLineIndicator(position: linePosition, color: supersetColor ?? DesignSystem.Colors.tint)
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

                // Superset position badge with letter label
                if let position = supersetPosition, let letter = supersetLetter {
                    SupersetBadge(
                        letter: letter,
                        position: position,
                        color: supersetColor ?? DesignSystem.Colors.tint
                    )
                }

                // Superset action button (visible in normal mode when closure provided)
                if let action = onSupersetAction {
                    Button(action: action) {
                        Image(systemName: routineExercise.isInSuperset ? "pencil.circle" : "link")
                            .font(.body)
                            .foregroundStyle(supersetColor ?? .secondary)
                    }
                    .buttonStyle(.plain)
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
