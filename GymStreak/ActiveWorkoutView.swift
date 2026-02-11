import SwiftUI

struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingCancelAlert = false
    @State private var showingFinishConfirmation = false
    @State private var showingSaveOptions = false
    @State private var showingRestTimerSheet = false
    @State private var showingAddExercise = false
    @State private var exerciseToDelete: WorkoutExercise?
    @State private var expandedSetId: UUID?
    @State private var lastActiveExerciseId: UUID?

    var body: some View {
        ZStack {
            // Main Content
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let session = viewModel.currentSession {
                        ForEach(Array(session.exercisesGroupedBySupersets.enumerated()), id: \.offset) { groupIndex, exerciseGroup in
                            if exerciseGroup.count > 1 {
                                // Superset group
                                SupersetWorkoutGroupView(exerciseCount: exerciseGroup.count) {
                                    ForEach(Array(exerciseGroup.enumerated()), id: \.element.id) { index, workoutExercise in
                                        ExerciseCard(
                                            workoutExercise: workoutExercise,
                                            viewModel: viewModel,
                                            isCurrentExercise: isCurrentExercise(workoutExercise),
                                            expandedSetId: $expandedSetId,
                                            lastActiveExerciseId: $lastActiveExerciseId,
                                            supersetPosition: index + 1,
                                            supersetTotal: exerciseGroup.count,
                                            onDelete: {
                                                exerciseToDelete = workoutExercise
                                            },
                                            onSetCompleted: {
                                                withAnimation(.snappy(duration: 0.35)) {
                                                    expandedSetId = nil
                                                }
                                            }
                                        )
                                    }
                                }
                            } else if let workoutExercise = exerciseGroup.first {
                                // Single exercise
                                ExerciseCard(
                                    workoutExercise: workoutExercise,
                                    viewModel: viewModel,
                                    isCurrentExercise: isCurrentExercise(workoutExercise),
                                    expandedSetId: $expandedSetId,
                                    lastActiveExerciseId: $lastActiveExerciseId,
                                    onDelete: {
                                        exerciseToDelete = workoutExercise
                                    },
                                    onSetCompleted: {
                                        withAnimation(.snappy(duration: 0.35)) {
                                            expandedSetId = nil
                                        }
                                    }
                                )
                            }
                        }

                        // Add Exercise Button - Card-style with chevron (navigation pattern)
                        Button {
                            showingAddExercise = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(DesignSystem.Colors.success)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("workout.add_exercise".localized)
                                        .font(.headline)
                                    Text("workout.add_exercise.description".localized)
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 16)
                        .accessibilityLabel("accessibility.add_exercise".localized)
                        .accessibilityHint("accessibility.add_exercise.hint".localized)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    TimerHeader(viewModel: viewModel)

                    // Compact Rest Timer (shows when sheet is dismissed but timer is active)
                    if viewModel.isRestTimerActive && !showingRestTimerSheet {
                        CompactRestTimer(
                            viewModel: viewModel,
                            onExpand: {
                                showingRestTimerSheet = true
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ActionBar(
                    onCancel: {
                        showingCancelAlert = true
                    },
                    onFinish: {
                        showingFinishConfirmation = true
                    }
                )
            }
        }
        .alert("workout.cancel.title".localized, isPresented: $showingCancelAlert) {
            Button("workout.cancel.discard".localized, role: .destructive) {
                viewModel.cancelWorkout()
                dismiss()
            }
            Button("workout.cancel.keep".localized, role: .cancel) {}
        } message: {
            Text("workout.cancel.message".localized)
        }
        .alert("workout.complete.title".localized, isPresented: $viewModel.showingWorkoutCompletePrompt) {
            Button("workout.complete.finish".localized) {
                showingSaveOptions = true
            }
            Button("workout.complete.continue".localized, role: .cancel) {
                viewModel.resumeAfterCompletionPrompt()
            }
        } message: {
            if let session = viewModel.currentSession {
                Text("workout.complete.message".localized(session.totalSetsCount))
            }
        }
        .sheet(item: $exerciseToDelete) { exercise in
            DeleteExerciseConfirmationView(
                exercise: exercise,
                onConfirm: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.removeExerciseFromWorkout(exercise)
                    }
                    exerciseToDelete = nil
                },
                onCancel: {
                    exerciseToDelete = nil
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .alert("workout.finish.title".localized, isPresented: $showingFinishConfirmation) {
            Button("workout.finish.continue".localized) {}
            Button("workout.finish.save".localized) {
                viewModel.pauseForCompletion()
                showingSaveOptions = true
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            if let session = viewModel.currentSession {
                Text("workout.completed_sets".localized(session.completedSetsCount, session.totalSetsCount))
            }
        }
        .tint(DesignSystem.Colors.textPrimary)
        .sheet(isPresented: $showingSaveOptions) {
            SaveWorkoutView(viewModel: viewModel) {
                dismiss()
            }
        }
        .sheet(isPresented: $showingRestTimerSheet) {
            RestTimerView(viewModel: viewModel, onDismiss: {
                showingRestTimerSheet = false
            })
            .presentationDetents([.height(320), .medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToWorkoutView(workoutViewModel: viewModel, exercisesViewModel: exercisesViewModel)
        }
        .onChange(of: viewModel.isRestTimerActive) { _, isActive in
            if isActive {
                // Auto-show sheet when timer starts
                showingRestTimerSheet = true
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                // Save timer state when app goes to background
                viewModel.saveTimerState()
            case .active:
                // Restore timer state when app becomes active
                viewModel.restoreTimerState()
            case .inactive:
                // App is transitioning, no action needed
                break
            @unknown default:
                break
            }
        }
    }

    private func isCurrentExercise(_ exercise: WorkoutExercise) -> Bool {
        // If user has interacted with a specific exercise, highlight that one
        if let lastActiveId = lastActiveExerciseId {
            return exercise.id == lastActiveId
        }

        // Otherwise, highlight the exercise with the next incomplete set
        guard let nextSet = viewModel.findNextIncompleteSet() else {
            return false
        }
        return nextSet.exercise.id == exercise.id
    }
}

// MARK: - Timer Header

struct TimerHeader: View {
    @ObservedObject var viewModel: WorkoutViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("workout.time".localized)
                        .font(.onyxCaption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(viewModel.formatDuration(viewModel.elapsedTime))
                        .font(.onyxNumberLarge)
                }

                Spacer()

                if let session = viewModel.currentSession {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("workout.progress".localized)
                            .font(.onyxCaption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                        Text("\(session.completedSetsCount)/\(session.totalSetsCount)")
                            .font(.onyxHeader)
                    }
                }
            }

            // Progress Bar
            if let session = viewModel.currentSession, session.totalSetsCount > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(DesignSystem.Colors.divider)
                            .frame(height: 6)
                            .clipShape(Capsule())

                        Rectangle()
                            .fill(DesignSystem.Colors.tint)
                            .frame(width: geometry.size.width * CGFloat(session.completedSetsCount) / CGFloat(session.totalSetsCount), height: 6)
                            .clipShape(Capsule())
                            .animation(.spring, value: session.completedSetsCount)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding()
        .background(DesignSystem.Colors.card)
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    let workoutExercise: WorkoutExercise
    @ObservedObject var viewModel: WorkoutViewModel
    let isCurrentExercise: Bool
    @Binding var expandedSetId: UUID?
    @Binding var lastActiveExerciseId: UUID?
    var supersetPosition: Int? = nil
    var supersetTotal: Int? = nil
    var onDelete: (() -> Void)?
    @State private var showingRestTimeConfig = false
    var onSetCompleted: (() -> Void)?

    // Computed property to get current rest time from the exercise's sets
    private var exerciseRestTime: TimeInterval {
        workoutExercise.setsList.first?.restTime ?? 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise Header
            HStack {
                MuscleGroupAbbreviationBadge(
                    muscleGroups: workoutExercise.muscleGroups,
                    isActive: isCurrentExercise
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutExercise.exerciseName)
                        .font(.headline)

                    Text("exercise.sets_completed".localized(workoutExercise.completedSetsCount, workoutExercise.setsList.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Superset position badge
                if let position = supersetPosition, let total = supersetTotal {
                    SupersetBadge(position: position, total: total)
                }

                if workoutExercise.completedSetsCount == workoutExercise.setsList.count {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                        .symbolEffect(.bounce, value: workoutExercise.completedSetsCount)
                }

                // Delete button
                if let onDelete = onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Rest Timer Configuration
            RestTimerConfigView(
                restTime: Binding(
                    get: { exerciseRestTime },
                    set: { newValue in
                        viewModel.updateRestTimeForExercise(workoutExercise, restTime: newValue)
                    }
                ),
                isExpanded: $showingRestTimeConfig,
                showToggle: true,
                onRestTimeChange: { newValue in
                    viewModel.updateRestTimeForExercise(workoutExercise, restTime: newValue)
                }
            )

            // Sets List
            ForEach(workoutExercise.setsList.sorted(by: { $0.order < $1.order }), id: \.id) { set in
                WorkoutSetRow(
                    set: set,
                    workoutExercise: workoutExercise,
                    viewModel: viewModel,
                    isNextSet: isNextSet(set),
                    isExpanded: expandedSetId == set.id,
                    onToggleExpand: {
                        withAnimation(.snappy(duration: 0.35)) {
                            if expandedSetId == set.id {
                                expandedSetId = nil
                            } else {
                                expandedSetId = set.id
                            }
                            // Mark this exercise as active when user interacts with it
                            lastActiveExerciseId = workoutExercise.id
                        }
                    },
                    onSetInteraction: {
                        // Mark this exercise as active when user uncompletes a set
                        lastActiveExerciseId = workoutExercise.id
                    },
                    onSetCompleted: {
                        // Collapse the set when it's marked as complete
                        onSetCompleted?()
                        // Clear lastActiveExerciseId so automatic navigation takes over
                        lastActiveExerciseId = nil
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
            }

            // Add Set Button - Lightweight, in-context, repeatable action
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.addSetToExercise(workoutExercise)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("accessibility.add_set".localized(workoutExercise.exerciseName))
            .accessibilityHint("accessibility.add_set.hint".localized)
        }
        .padding()
        .background(isCurrentExercise ? DesignSystem.Colors.tint.opacity(0.1) : DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                .strokeBorder(isCurrentExercise ? DesignSystem.Colors.tint : Color.clear, lineWidth: 2)
        )
    }

    private func isNextSet(_ set: WorkoutSet) -> Bool {
        // Only highlight next set if this is the current exercise
        guard isCurrentExercise else {
            return false
        }

        // Find the first incomplete set in THIS exercise
        let incompleteSetsInExercise = workoutExercise.setsList
            .sorted(by: { $0.order < $1.order })
            .filter { !$0.isCompleted }

        guard let firstIncompleteSet = incompleteSetsInExercise.first else {
            return false
        }

        return firstIncompleteSet.id == set.id
    }
}

// MARK: - Workout Set Row

struct WorkoutSetRow: View {
    let set: WorkoutSet
    let workoutExercise: WorkoutExercise
    @ObservedObject var viewModel: WorkoutViewModel
    let isNextSet: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSetInteraction: () -> Void
    let onSetCompleted: () -> Void

    @State private var editingReps: Int
    @State private var editingWeight: Double
    @State private var initialReps: Int
    @State private var initialWeight: Double
    @State private var repsBannerDismissed = false
    @State private var weightBannerDismissed = false
    @State private var showingDeleteSetAlert = false

    init(set: WorkoutSet, workoutExercise: WorkoutExercise, viewModel: WorkoutViewModel, isNextSet: Bool, isExpanded: Bool, onToggleExpand: @escaping () -> Void, onSetInteraction: @escaping () -> Void, onSetCompleted: @escaping () -> Void) {
        self.set = set
        self.workoutExercise = workoutExercise
        self.viewModel = viewModel
        self.isNextSet = isNextSet
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onSetInteraction = onSetInteraction
        self.onSetCompleted = onSetCompleted
        self._editingReps = State(initialValue: set.actualReps)
        self._editingWeight = State(initialValue: set.actualWeight)
        self._initialReps = State(initialValue: set.actualReps)
        self._initialWeight = State(initialValue: set.actualWeight)
    }

    // Computed property to check if reps have changed
    private var repsChanged: Bool {
        editingReps != initialReps
    }

    // Computed property to check if weight has changed
    private var weightChanged: Bool {
        editingWeight != initialWeight
    }

    // Check if exercise has multiple incomplete sets
    private var hasMultipleIncompleteSets: Bool {
        workoutExercise.setsList.filter { !$0.isCompleted }.count > 1
    }

    // Apply current reps to all incomplete sets in this exercise
    private func applyRepsToAllIncompleteSets() {
        for workoutSet in workoutExercise.setsList where !workoutSet.isCompleted {
            viewModel.updateSet(workoutSet, reps: editingReps, weight: workoutSet.actualWeight)
        }
    }

    // Apply current weight to all incomplete sets in this exercise
    private func applyWeightToAllIncompleteSets() {
        for workoutSet in workoutExercise.setsList where !workoutSet.isCompleted {
            viewModel.updateSet(workoutSet, reps: workoutSet.actualReps, weight: editingWeight)
        }
    }

    private var backgroundColor: Color {
        if isExpanded {
            return DesignSystem.Colors.cardElevated
        } else if isNextSet {
            return DesignSystem.Colors.tint.opacity(0.1)
        } else {
            return Color.clear
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Set Header
            Button(action: {
                if !isExpanded {
                    // Reset banners when opening
                    repsBannerDismissed = false
                    weightBannerDismissed = false
                    initialReps = set.actualReps
                    initialWeight = set.actualWeight
                }
                // Haptic feedback for expand/collapse
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleExpand()
            }) {
                HStack(spacing: 12) {
                    // Completion Button (toggleable)
                    Button {
                        if set.isCompleted {
                            viewModel.uncompleteSet(set)
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            // Notify that user interacted with this exercise
                            onSetInteraction()
                        } else {
                            viewModel.completeSet(workoutExercise: workoutExercise, set: set)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            // Always call onSetCompleted to clear lastActiveExerciseId and allow auto-navigation
                            onSetCompleted()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(set.isCompleted ? DesignSystem.Colors.success : (isNextSet ? DesignSystem.Colors.tint : DesignSystem.Colors.textSecondary), lineWidth: 2)
                                .frame(width: 28, height: 28)

                            if set.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(DesignSystem.Colors.success)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Set Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text("set.number".localized(set.order + 1))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text("set.reps".localized(set.actualReps))
                            Text("×")
                                .foregroundStyle(.secondary)
                            Text("set.weight".localized(set.actualWeight))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Completion time badge (if completed and not expanded)
                    if set.isCompleted && !isExpanded, let completedAt = set.completedAt {
                        Text(completedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Expand/Collapse indicator
                    Image(systemName: "chevron.down")
                        .font(isExpanded ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                        .foregroundStyle(isExpanded ? DesignSystem.Colors.tint : DesignSystem.Colors.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("accessibility.set.label".localized(set.order + 1, set.actualReps, set.actualWeight))
            .accessibilityHint(isExpanded ? "accessibility.set.hint.expanded".localized : "accessibility.set.hint.collapsed".localized)
            .accessibilityAddTraits(.isButton)

            // Expanded inline editor
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(spacing: 12) {
                    VStack(spacing: 16) {
                        // Reps input with contextual banner
                        VStack(spacing: 8) {
                            HorizontalStepper(
                                title: "set.reps_label".localized,
                                value: $editingReps,
                                range: 1...100,
                                step: 1
                            ) { newValue in
                                viewModel.updateSet(set, reps: newValue, weight: editingWeight)
                            }

                            // Reps Apply to All Banner
                            if hasMultipleIncompleteSets && repsChanged && !repsBannerDismissed {
                                ApplyToAllBanner(
                                    type: .reps,
                                    setCount: workoutExercise.setsList.filter { !$0.isCompleted }.count,
                                    onApply: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            applyRepsToAllIncompleteSets()
                                            repsBannerDismissed = true
                                            // Update initial reps so banner doesn't reappear
                                            initialReps = editingReps
                                        }
                                    },
                                    onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            repsBannerDismissed = true
                                        }
                                    }
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
                                viewModel.updateSet(set, reps: editingReps, weight: newValue)
                            }

                            // Weight Apply to All Banner
                            if hasMultipleIncompleteSets && weightChanged && !weightBannerDismissed {
                                ApplyToAllBanner(
                                    type: .weight,
                                    setCount: workoutExercise.setsList.filter { !$0.isCompleted }.count,
                                    onApply: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            applyWeightToAllIncompleteSets()
                                            weightBannerDismissed = true
                                            // Update initial weight so banner doesn't reappear
                                            initialWeight = editingWeight
                                        }
                                    },
                                    onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            weightBannerDismissed = true
                                        }
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }
                        }

                        // Show planned values for reference
                        HStack {
                            Text("set.planned".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("set.planned_detail".localized(set.plannedReps, set.plannedWeight))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
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
                }
                .padding(.horizontal, 12)
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
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM)
                .strokeBorder(isExpanded ? DesignSystem.Colors.tint.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(set.isCompleted ? 0.7 : 1.0)
        .onChange(of: set.actualReps) { _, newValue in
            editingReps = newValue
        }
        .onChange(of: set.actualWeight) { _, newValue in
            editingWeight = newValue
        }
        .alert("set.delete.title".localized, isPresented: $showingDeleteSetAlert) {
            Button("set.delete.confirm".localized, role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.removeSetFromExercise(set, from: workoutExercise)
                }
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("set.delete.message".localized)
        }
    }
}

// MARK: - Action Bar

struct ActionBar: View {
    let onCancel: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(DesignSystem.Colors.divider)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Text("workout.cancel".localized)
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignSystem.Dimensions.buttonHeight)
                }
                .buttonStyle(.bordered)

                Button {
                    onFinish()
                } label: {
                    Label("workout.finish".localized, systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignSystem.Dimensions.buttonHeight)
                }
                .buttonStyle(.onyxProminent)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
        }
    }
}

// MARK: - Compact Rest Timer

struct CompactRestTimer: View {
    @ObservedObject var viewModel: WorkoutViewModel
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Circular progress indicator (small)
            ZStack {
                Circle()
                    .stroke(DesignSystem.Colors.divider, lineWidth: 3)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(DesignSystem.Colors.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }

            // Timer text
            VStack(alignment: .leading, spacing: 2) {
                Text("rest_timer.title".localized)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text(viewModel.formatTime(viewModel.restTimeRemaining))
                    .font(.onyxNumber)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Skip button
                Button {
                    viewModel.stopRestTimer()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Expand button
                Button {
                    onExpand()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(DesignSystem.Colors.divider),
            alignment: .bottom
        )
    }

    private var progress: CGFloat {
        let totalDuration = viewModel.restDuration
        guard totalDuration > 0 else { return 0 }

        return CGFloat(viewModel.restTimeRemaining / totalDuration)
    }
}

// MARK: - Delete Exercise Confirmation View

struct DeleteExerciseConfirmationView: View {
    let exercise: WorkoutExercise
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Drag indicator area
            Spacer()
                .frame(height: 8)

            // Icon
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)

            // Content
            VStack(spacing: 8) {
                Text("delete_exercise.title".localized)
                    .font(.title3.bold())

                let completedCount = exercise.completedSetsCount
                if completedCount > 0 {
                    Text("delete_exercise.message_with_sets".localized(completedCount, completedCount == 1 ? "" : "s", exercise.exerciseName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("delete_exercise.message_no_sets".localized(exercise.exerciseName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)

            // Buttons
            VStack(spacing: 12) {
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    Text("delete_exercise.remove".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    onCancel()
                } label: {
                    Text("delete_exercise.cancel".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.card)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD))
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 20)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Superset Workout Group View

struct SupersetWorkoutGroupView<Content: View>: View {
    let exerciseCount: Int
    let content: Content

    init(exerciseCount: Int, @ViewBuilder content: () -> Content) {
        self.exerciseCount = exerciseCount
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Superset header
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                Text("Superset")
                    .font(.caption.weight(.semibold))
                Text("(\(exerciseCount) exercises)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(DesignSystem.Colors.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.tint.opacity(0.15))
            )
            .padding(.bottom, 8)

            // Content with connecting visual
            HStack(alignment: .top, spacing: 0) {
                // Vertical connecting line
                Rectangle()
                    .fill(DesignSystem.Colors.tint.opacity(0.4))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.leading, 4)

                // Grouped exercises
                VStack(spacing: 12) {
                    content
                }
                .padding(.leading, 12)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                .fill(DesignSystem.Colors.tint.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                .strokeBorder(DesignSystem.Colors.tint.opacity(0.2), lineWidth: 1)
        )
    }
}
