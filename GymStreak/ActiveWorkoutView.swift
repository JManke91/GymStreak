import SwiftUI

struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingCancelAlert = false
    @State private var showingFinishConfirmation = false
    @State private var showingSaveOptions = false
    @State private var showingRestTimerSheet = false
    @State private var editingSet: WorkoutSet?

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
                                editingSet: $editingSet
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
        .sheet(item: $editingSet) { set in
            EditSetSheet(set: set, viewModel: viewModel)
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
    @Binding var editingSet: WorkoutSet?

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
                    onEdit: {
                        editingSet = set
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
        switch workoutExercise.muscleGroup {
        case "Arms": return "figure.arms.open"
        case "Legs": return "figure.walk"
        case "Chest": return "heart.fill"
        case "Back": return "figure.cooldown"
        case "Shoulders": return "figure.arms.open"
        case "Core": return "figure.core.training"
        case "Glutes": return "figure.strengthtraining.traditional"
        case "Calves": return "figure.walk"
        case "Full Body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }

    private func isNextSet(_ set: WorkoutSet) -> Bool {
        guard let nextSet = viewModel.findNextIncompleteSet() else {
            return false
        }
        return nextSet.set.id == set.id
    }
}

// MARK: - Workout Set Row

struct WorkoutSetRow: View {
    let set: WorkoutSet
    let workoutExercise: WorkoutExercise
    @ObservedObject var viewModel: WorkoutViewModel
    let isNextSet: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion Button
            Button {
                if !set.isCompleted {
                    viewModel.completeSet(workoutExercise: workoutExercise, set: set)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
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
            .disabled(set.isCompleted)

            // Set Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Set \(set.order + 1)")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    Text("\(set.actualReps) reps")
                    Text("×")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f kg", set.actualWeight))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Edit button (only for incomplete sets)
            if !set.isCompleted {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            } else if let completedAt = set.completedAt {
                Text(completedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isNextSet ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(set.isCompleted ? 0.7 : 1.0)
    }
}

// MARK: - Edit Set Sheet

struct EditSetSheet: View {
    let set: WorkoutSet
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reps: Int
    @State private var weight: Double

    init(set: WorkoutSet, viewModel: WorkoutViewModel) {
        self.set = set
        self.viewModel = viewModel
        self._reps = State(initialValue: set.actualReps)
        self._weight = State(initialValue: set.actualWeight)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Stepper("Reps: \(reps)", value: $reps, in: 1...100)
                        .font(.headline)

                    HStack {
                        Text("Weight:")
                            .font(.headline)

                        Spacer()

                        TextField("Weight", value: $weight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)

                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Planned") {
                        Text("\(set.plannedReps) reps × \(String(format: "%.1f kg", set.plannedWeight))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Set \(set.order + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.updateSet(set, reps: reps, weight: weight)
                        dismiss()
                    }
                }
            }
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
