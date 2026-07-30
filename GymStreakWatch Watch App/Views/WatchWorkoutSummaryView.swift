import SwiftUI
import WatchKit

struct WatchWorkoutSummaryView: View {
    let summary: WatchWorkoutSummary
    let onDismiss: () -> Void

    @EnvironmentObject private var viewModel: WatchWorkoutViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxWatch.Spacing.lg) {
                headerSection

                if viewModel.templateWasUpdated {
                    templateUpdateBanner
                }

                statsCard
                exercisesCard
                doneButton
            }
            .padding(.horizontal, OnyxWatch.Spacing.md)
            .padding(.bottom, OnyxWatch.Spacing.xl)
        }
        .background(OnyxWatch.Colors.background.ignoresSafeArea())
        .onAppear {
            WKInterfaceDevice.current().play(.success)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: OnyxWatch.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(OnyxWatch.Colors.tint)

            Text("Workout Complete")
                .font(.watchHeader)
                .foregroundStyle(OnyxWatch.Colors.textPrimary)

            Text(summary.routineName)
                .font(.watchCaption)
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
        }
        .padding(.top, OnyxWatch.Spacing.md)
    }

    // MARK: - Template Update Banner

    private var templateUpdateBanner: some View {
        HStack(spacing: OnyxWatch.Spacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(OnyxWatch.Colors.textOnTint)

            Text("Template updated")
                .font(.watchCaption)
                .foregroundStyle(OnyxWatch.Colors.textOnTint)
        }
        .padding(.horizontal, OnyxWatch.Spacing.md)
        .padding(.vertical, OnyxWatch.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusMD)
                .fill(OnyxWatch.Colors.tint)
        )
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: OnyxWatch.Spacing.md) {
            statRow(
                icon: "clock.fill",
                iconColor: OnyxWatch.Colors.tint,
                label: String(localized: "Duration"),
                value: summary.formattedDuration
            )

            Divider()
                .background(OnyxWatch.Colors.divider)

            statRow(
                icon: "dumbbell.fill",
                iconColor: OnyxWatch.Colors.tint,
                label: String(localized: "Sets"),
                value: "\(summary.completedSets)/\(summary.totalSets) (\(summary.completionPercentage)%)"
            )

            if let calories = summary.activeCalories, calories > 0 {
                Divider()
                    .background(OnyxWatch.Colors.divider)

                statRow(
                    icon: "flame.fill",
                    iconColor: OnyxWatch.Colors.warning,
                    label: String(localized: "Calories"),
                    value: String(localized: "\(calories) cal")
                )
            }
        }
        .padding(OnyxWatch.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusMD)
                .fill(OnyxWatch.Colors.card)
        )
    }

    private func statRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(label)
                .font(.watchCaption)
                .foregroundStyle(OnyxWatch.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(.watchNumber)
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
        }
    }

    // MARK: - Exercises Card

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: OnyxWatch.Spacing.md) {
            Text("Exercises")
                .font(.watchCaption)
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
                .padding(.horizontal, OnyxWatch.Spacing.sm)

            // Lazy: each row now also builds an overload prompt, and the list
            // grows with the routine rather than being a fixed handful.
            LazyVStack(spacing: OnyxWatch.Spacing.sm) {
                ForEach(summary.exercises) { exercise in
                    // Resolved once into the view model, never looked up here:
                    // one row's state walks the routine, its slots and their
                    // alternatives.
                    let overloadRow = viewModel.summaryOverloadRows[exercise.id]
                    VStack(spacing: OnyxWatch.Spacing.sm) {
                        exerciseRow(exercise, hasOverloadPrompt: overloadRow != nil)
                        if let overloadRow {
                            SummaryOverloadPromptView(state: overloadRow.state) {
                                viewModel.presentSummaryOverload(slotID: exercise.id)
                            }
                        }
                    }
                }
            }
            .padding(OnyxWatch.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusMD)
                    .fill(OnyxWatch.Colors.card)
            )
        }
    }

    private func exerciseRow(
        _ exercise: WatchWorkoutSummary.ExerciseSummary,
        hasOverloadPrompt: Bool
    ) -> some View {
        HStack(spacing: OnyxWatch.Spacing.md) {
            Image(systemName: exercise.isComplete ? "checkmark.circle.fill" : "circle.badge.minus")
                .font(.caption2)
                .foregroundStyle(exercise.isComplete ? OnyxWatch.Colors.success : OnyxWatch.Colors.warning)

            Text(exercise.name)
                .font(.watchCaption)
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
                .lineLimit(1)

            // Rep-goal trophy — the passive form of the achievement. Dropped
            // when the prompt below says the same thing and offers to act on
            // it; kept when there is nothing actionable (the routine slot was
            // deleted on iPhone), so the accomplishment is still acknowledged.
            if exercise.repGoalAchieved && !hasOverloadPrompt {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Text("\(exercise.completedSets)/\(exercise.totalSets)")
                .font(.watchNumberSmall)
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(.watchHeader)
                .foregroundStyle(OnyxWatch.Colors.textOnTint)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OnyxWatch.Colors.tint)
    }
}

#Preview {
    WatchWorkoutSummaryView(
        summary: WatchWorkoutSummary(
            routineName: "Push Day",
            duration: 2345,
            completedSets: 8,
            totalSets: 9,
            completionPercentage: 89,
            activeCalories: 234,
            exercises: [
                .init(id: UUID(), name: "Bench Press", muscleGroup: "Chest", completedSets: 3, totalSets: 3, isComplete: true, repGoalAchieved: true),
                .init(id: UUID(), name: "Shoulder Press", muscleGroup: "Shoulders", completedSets: 3, totalSets: 3, isComplete: true, repGoalAchieved: false),
                .init(id: UUID(), name: "Tricep Pushdown", muscleGroup: "Triceps", completedSets: 2, totalSets: 3, isComplete: false, repGoalAchieved: false)
            ]
        ),
        onDismiss: {}
    )
    .environmentObject(WatchWorkoutViewModel(
        healthKitManager: WatchHealthKitManager(),
        connectivityManager: WatchConnectivityManager.shared,
        routineStore: RoutineStore(syncState: WatchSyncStateStore())
    ))
}
