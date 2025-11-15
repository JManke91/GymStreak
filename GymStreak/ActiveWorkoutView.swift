import SwiftUI

struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingCancelAlert = false
    @State private var showingFinishConfirmation = false
    @State private var showingSaveOptions = false
    @State private var showingRestTimerSheet = false
    @State private var expandedSetId: UUID?
    @State private var lastActiveExerciseId: UUID?

    var body: some View {
        ZStack {
            // Main Content
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let session = viewModel.currentSession {
                        ForEach(session.workoutExercises.sorted(by: { $0.order < $1.order }), id: \.id) { workoutExercise in
                            ExerciseCard(
                                workoutExercise: workoutExercise,
                                viewModel: viewModel,
                                isCurrentExercise: isCurrentExercise(workoutExercise),
                                expandedSetId: $expandedSetId,
                                lastActiveExerciseId: $lastActiveExerciseId
                            )
                        }
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
        .alert("Cancel Workout?", isPresented: $showingCancelAlert) {
            Button("Discard Workout", role: .destructive) {
                viewModel.cancelWorkout()
                dismiss()
            }
            Button("Keep Working Out", role: .cancel) {}
        } message: {
            Text("Your progress will not be saved.")
        }
        .confirmationDialog("Finish Workout", isPresented: $showingFinishConfirmation) {
            Button("Save Workout") {
                viewModel.pauseForCompletion()
                showingSaveOptions = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let session = viewModel.currentSession {
                Text("You completed \(session.completedSetsCount) of \(session.totalSetsCount) sets.")
            }
        }
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
        .onChange(of: viewModel.isRestTimerActive) { _, isActive in
            if isActive {
                // Auto-show sheet when timer starts
                showingRestTimerSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.pauseWorkout()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.resumeWorkout()
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
                    Text("Workout Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(viewModel.formatDuration(viewModel.elapsedTime))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }

                Spacer()

                if let session = viewModel.currentSession {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(session.completedSetsCount)/\(session.totalSetsCount)")
                            .font(.headline)
                    }
                }
            }

            // Progress Bar
            if let session = viewModel.currentSession, session.totalSetsCount > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)
                            .clipShape(Capsule())

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * CGFloat(session.completedSetsCount) / CGFloat(session.totalSetsCount), height: 6)
                            .clipShape(Capsule())
                            .animation(.spring, value: session.completedSetsCount)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    let workoutExercise: WorkoutExercise
    @ObservedObject var viewModel: WorkoutViewModel
    let isCurrentExercise: Bool
    @Binding var expandedSetId: UUID?
    @Binding var lastActiveExerciseId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise Header
            HStack {
                Image(systemName: muscleGroupIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isCurrentExercise ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutExercise.exerciseName)
                        .font(.headline)

                    Text("\(workoutExercise.completedSetsCount)/\(workoutExercise.sets.count) sets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if workoutExercise.completedSetsCount == workoutExercise.sets.count {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                        .symbolEffect(.bounce, value: workoutExercise.completedSetsCount)
                }
            }

            // Sets List
            ForEach(workoutExercise.sets.sorted(by: { $0.order < $1.order }), id: \.id) { set in
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
                        // Mark this exercise as active when user completes/uncompletes a set
                        lastActiveExerciseId = workoutExercise.id
                    }
                )
            }
        }
        .padding()
        .background(isCurrentExercise ? Color.blue.opacity(0.1) : Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isCurrentExercise ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var muscleGroupIcon: String {
        MuscleGroups.icon(for: workoutExercise.muscleGroup)
    }

    private func isNextSet(_ set: WorkoutSet) -> Bool {
        // Only highlight next set if this is the current exercise
        guard isCurrentExercise else {
            return false
        }

        // Find the first incomplete set in THIS exercise
        let incompleteSetsInExercise = workoutExercise.sets
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

    @State private var editingReps: Int
    @State private var editingWeight: Double
    @State private var initialReps: Int
    @State private var initialWeight: Double
    @State private var repsBannerDismissed = false
    @State private var weightBannerDismissed = false

    init(set: WorkoutSet, workoutExercise: WorkoutExercise, viewModel: WorkoutViewModel, isNextSet: Bool, isExpanded: Bool, onToggleExpand: @escaping () -> Void, onSetInteraction: @escaping () -> Void) {
        self.set = set
        self.workoutExercise = workoutExercise
        self.viewModel = viewModel
        self.isNextSet = isNextSet
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onSetInteraction = onSetInteraction
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
        workoutExercise.sets.filter { !$0.isCompleted }.count > 1
    }

    // Apply current reps to all incomplete sets in this exercise
    private func applyRepsToAllIncompleteSets() {
        for workoutSet in workoutExercise.sets where !workoutSet.isCompleted {
            viewModel.updateSet(workoutSet, reps: editingReps, weight: workoutSet.actualWeight)
        }
    }

    // Apply current weight to all incomplete sets in this exercise
    private func applyWeightToAllIncompleteSets() {
        for workoutSet in workoutExercise.sets where !workoutSet.isCompleted {
            viewModel.updateSet(workoutSet, reps: workoutSet.actualReps, weight: editingWeight)
        }
    }

    private var backgroundColor: Color {
        if isExpanded {
            return Color(.tertiarySystemGroupedBackground)
        } else if isNextSet {
            return Color.blue.opacity(0.1)
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
                        } else {
                            viewModel.completeSet(workoutExercise: workoutExercise, set: set)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        // Notify that user interacted with this exercise
                        onSetInteraction()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(set.isCompleted ? Color.green : (isNextSet ? Color.blue : Color.secondary), lineWidth: 2)
                                .frame(width: 28, height: 28)

                            if set.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Set Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set \(set.order + 1)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text("\(set.actualReps) reps")
                            Text("×")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f kg", set.actualWeight))
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
                        .foregroundStyle(isExpanded ? .blue : .secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Set \(set.order + 1): \(set.actualReps) reps, \(String(format: "%.2f", set.actualWeight)) kilograms")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand and edit")
            .accessibilityAddTraits(.isButton)

            // Expanded inline editor
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(spacing: 12) {
                    // Completed badge
                    if set.isCompleted, let completedAt = set.completedAt {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Completed at \(completedAt, style: .time)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }

                    VStack(spacing: 16) {
                        // Reps input with contextual banner
                        VStack(spacing: 8) {
                            HorizontalStepper(
                                title: "Reps",
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
                                    setCount: workoutExercise.sets.filter { !$0.isCompleted }.count,
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
                                title: "Weight (kg)",
                                weight: $editingWeight,
                                increment: 0.25
                            ) { newValue in
                                viewModel.updateSet(set, reps: editingReps, weight: newValue)
                            }

                            // Weight Apply to All Banner
                            if hasMultipleIncompleteSets && weightChanged && !weightBannerDismissed {
                                ApplyToAllBanner(
                                    type: .weight,
                                    setCount: workoutExercise.sets.filter { !$0.isCompleted }.count,
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
                            Text("Planned:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(set.plannedReps) reps × \(String(format: "%.2f kg", set.plannedWeight))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
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
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isExpanded ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(set.isCompleted ? 0.7 : 1.0)
        .onChange(of: set.actualReps) { _, newValue in
            editingReps = newValue
        }
        .onChange(of: set.actualWeight) { _, newValue in
            editingWeight = newValue
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

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)

                Button {
                    onFinish()
                } label: {
                    Label("Finish Workout", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
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
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    .frame(width: 32, height: 32)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }

            // Timer text
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.formatTime(viewModel.restTimeRemaining))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
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
                        .foregroundStyle(.orange)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }

    private var progress: CGFloat {
        guard viewModel.currentSession != nil,
              let nextSet = viewModel.findNextIncompleteSet() else {
            return 0
        }

        let totalDuration = nextSet.set.restTime
        guard totalDuration > 0 else { return 0 }

        return CGFloat(viewModel.restTimeRemaining / totalDuration)
    }
}
