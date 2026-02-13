import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutSession
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var exerciseComparisons: [ExerciseComparisonResult] = []
    @State private var isLoadingComparisons = true

    var body: some View {
        List {
            // Summary Section
            Section {
                // Date and Time Range
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("workout_detail.date".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(workout.startTime, format: .dateTime.month().day().year())
                            .font(.headline)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("workout_detail.time".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timeRangeString)
                            .font(.headline)
                    }
                }

                LabeledContent("workout_detail.duration".localized) {
                    Text(formatDuration(workout.duration))
                        .font(.headline)
                }

                LabeledContent("workout_detail.sets_completed".localized) {
                    Text("workout_detail.sets_of".localized(workout.completedSetsCount, workout.totalSetsCount))
                        .font(.headline)
                }

                LabeledContent("workout_detail.completion".localized) {
                    HStack(spacing: 4) {
                        Text("\(workout.completionPercentage)%")
                            .font(.headline)
                        if workout.completionPercentage == 100 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                if workout.didUpdateTemplate {
                    Label("workout_detail.template_updated".localized, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("workout_detail.summary".localized)
            }

            // Notes Section
            if !workout.notes.isEmpty {
                Section {
                    Text(workout.notes)
                        .font(.body)
                } header: {
                    Text("save_workout.notes".localized)
                }
            }

            // Exercises Section with Comparison
            Section {
                if isLoadingComparisons {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(exerciseComparisons, id: \.exerciseName) { comparison in
                        WorkoutExerciseComparisonCard(
                            comparison: comparison,
                            workoutExercise: findWorkoutExercise(for: comparison.exerciseName)
                        )
                    }
                }
            } header: {
                Text("exercises.title".localized)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(workout.routineName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadComparisons()
        }
    }

    // MARK: - Computed Properties

    private var timeRangeString: String {
        let startFormatter = DateFormatter()
        startFormatter.timeStyle = .short
        startFormatter.dateStyle = .none

        let start = startFormatter.string(from: workout.startTime)

        if let endTime = workout.endTime {
            let end = startFormatter.string(from: endTime)
            return "\(start) - \(end)"
        } else {
            return start
        }
    }

    // MARK: - Helper Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private func loadComparisons() async {
        let service = ExerciseProgressService(modelContext: modelContext)
        exerciseComparisons = service.compareWithPrevious(workout: workout)
        isLoadingComparisons = false
    }

    private func findWorkoutExercise(for exerciseName: String) -> WorkoutExercise? {
        workout.workoutExercisesList.first { $0.exerciseName == exerciseName }
    }
}

// MARK: - Workout Exercise Comparison Card

struct WorkoutExerciseComparisonCard: View {
    let comparison: ExerciseComparisonResult
    let workoutExercise: WorkoutExercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise Header with Chart Link
            NavigationLink {
                if let exercise = workoutExercise {
                    ExerciseProgressChartView(exerciseName: exercise.exerciseName)
                }
            } label: {
                HStack {
                    if let exercise = workoutExercise {
                        MuscleGroupAbbreviationBadge(
                            muscleGroups: exercise.muscleGroups,
                            isActive: true
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(comparison.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if comparison.isFirstTime {
                            Text("progress.first_workout".localized)
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.tint)
                        } else if let previous = comparison.previousPerformance {
                            HStack(spacing: 4) {
                                Text("progress.compared_to_previous".localized)
                                Text("(\(previous.date, format: .dateTime.month(.abbreviated).day()))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Chart icon
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
            }
            .buttonStyle(.plain)

            // Sets Comparison Table
            VStack(spacing: 8) {
                // Header Row
                HStack {
                    Text("workout_detail.set".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)

                    if !comparison.isFirstTime {
                        Text("progress.last_time".localized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("progress.this_time".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                        .frame(width: 24)
                }
                .padding(.horizontal, 8)

                Divider()

                // Set Rows
                ForEach(comparison.currentPerformance.sets, id: \.setNumber) { setComparison in
                    SetComparisonRow(
                        setComparison: setComparison,
                        isFirstTime: comparison.isFirstTime
                    )
                }
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Set Comparison Row

struct SetComparisonRow: View {
    let setComparison: ExerciseComparisonResult.CurrentExercisePerformance.SetComparison
    let isFirstTime: Bool

    var body: some View {
        HStack {
            // Set Number
            Text("\(setComparison.setNumber)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)

            // Previous Performance (if not first time)
            if !isFirstTime {
                VStack(alignment: .leading, spacing: 2) {
                    if let prevReps = setComparison.previousReps,
                       let prevWeight = setComparison.previousWeight {
                        Text("\(prevReps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f kg", prevWeight))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("progress.new_exercise".localized)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.info)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Current Performance with Delta
            if setComparison.isCompleted {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(setComparison.currentReps) reps")
                            .font(.caption)
                        if let delta = setComparison.repsDelta, delta != 0 {
                            DeltaBadge(value: delta, unit: "")
                        }
                    }

                    HStack(spacing: 4) {
                        Text(String(format: "%.1f kg", setComparison.currentWeight))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let delta = setComparison.weightDelta, abs(delta) > 0.1 {
                            DeltaBadge(value: delta, unit: "kg", isWeight: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
                    .frame(width: 24)
            } else {
                Text("workout_detail.skipped".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .font(.body)
                    .frame(width: 24)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(setComparison.isCompleted ? Color.green.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Delta Badge

struct DeltaBadge: View {
    let value: Double
    let unit: String
    var isWeight: Bool = false

    private var intValue: Int? {
        isWeight ? nil : Int(value)
    }

    private var isPositive: Bool {
        value > 0
    }

    private var isNegative: Bool {
        value < 0
    }

    private var color: Color {
        if isPositive {
            return DesignSystem.Colors.success
        } else if isNegative {
            return DesignSystem.Colors.warning
        } else {
            return .secondary
        }
    }

    private var icon: String {
        if isPositive {
            return "arrow.up.right"
        } else if isNegative {
            return "arrow.down.right"
        } else {
            return "equal"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)

            if let intVal = intValue {
                Text(intVal > 0 ? "+\(intVal)" : "\(intVal)")
                    .font(.caption2.weight(.medium))
            } else {
                Text(value > 0 ? String(format: "+%.1f", value) : String(format: "%.1f", value))
                    .font(.caption2.weight(.medium))
            }

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
            }
        }
        .foregroundStyle(color)
    }
}

// Convenience initializer for Int values
extension DeltaBadge {
    init(value: Int, unit: String) {
        self.value = Double(value)
        self.unit = unit
        self.isWeight = false
    }
}
