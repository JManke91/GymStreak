//
//  HistoryView.swift
//  GymStreak
//

import SwiftUI

/// Stack destination for the AI Coach settings screen.
private struct AICoachSettingsDestination: Hashable {}

/// New top-level History tab replacing WorkoutHistoryView.
/// Hosts a segmented "Trainings / Fortschritt" control and drives navigation to detail views.
struct HistoryView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.scenePhase) private var scenePhase
#if DEBUG
    @State private var stallProbe = HistoryMainThreadStallProbe()
#endif
    private let aiCoachPreferences: AICoachPreferencesProviding
    private let aiCoachAvailability: AICoachAvailabilityProviding
    private let proactivePromptCoordinator: ProactivePromptCoordinating

    /// Owns everything this screen renders, precomputed. See `HistoryViewModel`.
    @State private var model: HistoryViewModel

    @State private var section: HistorySection = .trainings
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var workoutToDelete: WorkoutSession?
    @State private var showingDeleteAlert = false
    @State private var isRecovering = false
    /// Type-erased because the stack pushes workout ids, exercise models, period
    /// destinations and the AI Coach settings destination.
    @State private var path = NavigationPath()

    init(
        viewModel: WorkoutViewModel,
        historySnapshotProvider: HistorySnapshotProviding,
        aiCoachPreferences: AICoachPreferencesProviding,
        aiCoachAvailability: AICoachAvailabilityProviding,
        proactivePromptCoordinator: ProactivePromptCoordinating
    ) {
        self.viewModel = viewModel
        self.aiCoachPreferences = aiCoachPreferences
        self.aiCoachAvailability = aiCoachAvailability
        self.proactivePromptCoordinator = proactivePromptCoordinator
        self._model = State(
            initialValue: HistoryViewModel(provider: historySnapshotProvider)
        )
    }

    /// Change token for the Trainings snapshot. Replaces three separate triggers (`onAppear` +
    /// `onChange(history.count)` + `onChange(exerciseLibrarySignature)`) that could each fire a full
    /// double aggregation, up to three times per appearance.
    ///
    /// Explicit invalidation rather than retaining the full model array. Editing an existing
    /// workout and a CloudKit modify do not change a count, so callers bump this version whenever
    /// persisted History data changes.
    private struct DataToken: Equatable {
        let historyVersion: Int
        let currentDay: Date
    }

    /// Fortschritt's aggregation is a whole extra walk of the session graph, so it is keyed
    /// separately and only runs while that tab is the visible one. Deliberately *not* folded into
    /// `DataToken`: including `section` there made the segmented toggle re-run `computePRs` and the
    /// whole snapshot build, neither of which depends on which tab is showing.
    private struct FortschrittToken: Equatable {
        let data: DataToken
        let section: HistorySection
    }

    private var dataToken: DataToken {
        DataToken(
            historyVersion: viewModel.historyVersion,
            currentDay: currentDay
        )
    }

    private var fortschrittToken: FortschrittToken {
        FortschrittToken(data: dataToken, section: section)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HistoryHeaderView(
                            section: $section,
                            onOpenSettings: {
                                path.append(AICoachSettingsDestination())
                            },
                            onInteractionStarted: {
#if DEBUG
                                stallProbe.reset()
#endif
                            }
                        )
                        if !viewModel.orphanedWatchWorkouts.isEmpty {
                            PendingSyncBannerView(orphans: viewModel.orphanedWatchWorkouts) {
                                isRecovering = true
                                Task {
                                    // Recovery re-fetches, which bumps `historyVersion` and
                                    // re-fires the rebuild tasks on its own.
                                    await viewModel.recoverOrphanedWorkouts()
                                    isRecovering = false
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .disabled(isRecovering)
                        }
                        if viewModel.healthKitDeleteFailed {
                            HealthDeleteFailureBanner {
                                viewModel.dismissHealthKitDeleteNotice()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .transition(.opacity)
                        }
                        Group {
                            switch section {
                            case .trainings:
                                TrainingsTabView(
                                    snapshot: model.snapshot,
                                    aiCoachPreferences: aiCoachPreferences,
                                    aiCoachAvailability: aiCoachAvailability,
                                    proactivePromptCoordinator: proactivePromptCoordinator,
                                    hasLoaded: model.hasLoaded,
                                    didFailLoading: model.didFailLoading,
                                    onRetry: {
                                        Task { await refreshSnapshot() }
                                    },
                                    onDeleteRequested: requestDelete,
                                    onSelectWorkout: pushWorkout
                                )
                            case .fortschritt:
                                FortschrittTabView(
                                    model: model.fortschrittList,
                                    isLoading: model.isLoadingFortschritt,
                                    didFailLoading: model.didFailFortschritt,
                                    onRetry: {
                                        Task { await refreshFortschritt() }
                                    }
                                )
                            }
                        }
                        .padding(.top, 4)

                        Color.clear.frame(height: 60)
                    }
                    .animation(.easeInOut(duration: 0.25), value: viewModel.healthKitDeleteFailed)
                }
                .refreshable {
                    viewModel.refreshHistory()
                }
#if DEBUG
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .interacting {
                        stallProbe.reset()
                    }
                }
#endif
            }
            // Keep the tab root free of navigation chrome without passing that
            // preference to its pushed destinations.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { sessionId in
                if let session = viewModel.workoutSession(id: sessionId) {
                    WorkoutDetailView(workout: session, viewModel: viewModel)
                }
            }
            .navigationDestination(for: ExerciseWithHistory.self) { exercise in
                ExerciseProgressChartView(
                    exerciseName: exercise.name,
                    exerciseId: exercise.exerciseId,
                    availableExercises: exercise.allExercises
                )
            }
            .navigationDestination(for: PeriodRecapDestination.self) { dest in
                PeriodRecapView(initialRange: dest.range)
            }
            // Value-based like every other destination here: an isPresented push
            // is not represented in `path`, and the two views of the same stack
            // can then disagree (spurious pops, double pushes).
            .navigationDestination(for: AICoachSettingsDestination.self) { _ in
                AICoachSettingsView()
            }
            .onAppear {
#if DEBUG
                stallProbe.reset()
#endif
                Task { await viewModel.reconcileWatchWorkouts() }
            }
            // `.task(id:)` also cancels a superseded rebuild, which the three separate onChange
            // handlers it replaced could not.
            .task(id: dataToken) {
                await refreshSnapshot()
            }
            .task(id: fortschrittToken) {
                await refreshFortschritt()
            }
            .task {
                await observeDayBoundary()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-run the HK reconciler when the user returns to the app —
                // catches workouts saved on the watch while iOS was backgrounded.
                if newPhase == .active {
                    currentDay = Calendar.current.startOfDay(for: Date())
                    Task { await viewModel.reconcileWatchWorkouts() }
                }
            }
            .deleteWorkoutConfirmation(
                isPresented: $showingDeleteAlert,
                hasHealthKitWorkout: workoutToDelete?.healthKitWorkoutId != nil,
                onDelete: { alsoFromHealthKit in
                    if let workout = workoutToDelete {
                        // Deleting re-fetches, which bumps `historyVersion` and re-fires the
                        // rebuild tasks; rebuilding here as well would do the work twice.
                        viewModel.deleteWorkout(workout, alsoFromHealthKit: alsoFromHealthKit)
                        workoutToDelete = nil
                        HapticManager.shared.success()
                    }
                },
                onCancel: { workoutToDelete = nil }
            )
#if DEBUG
            .overlay(alignment: .bottomLeading) {
                HistoryMainThreadStallProbeOverlay(probe: stallProbe)
            }
#endif
        }
    }

    // MARK: - Actions

    /// Pushes a workout detail screen for the calendar's selected-day card.
    /// Trainings list rows use native `NavigationLink`s.
    private func pushWorkout(_ sessionId: UUID) {
        guard path.isEmpty else { return }
        path.append(sessionId)
    }

    /// Rows carry only a card id, so the `@Model` object is resolved here — the list itself never
    /// holds one.
    private func requestDelete(_ sessionId: UUID) {
        guard let session = viewModel.workoutSession(id: sessionId) else { return }
        workoutToDelete = session
        showingDeleteAlert = true
    }

    // MARK: - Data loading

    private func refreshSnapshot() async {
        guard await model.reloadTraining() else { return }
        proactivePromptCoordinator.evaluate(
            lastMonth: model.snapshot.lastMonth
        )
    }

    private func refreshFortschritt() async {
        guard section == .fortschritt else { return }
        await model.reloadFortschritt()
    }

    private func observeDayBoundary() async {
        while !Task.isCancelled {
            let calendar = Calendar.current
            let now = Date()
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: now)
            ) else { return }

            do {
                try await Task.sleep(for: .seconds(max(1, nextDay.timeIntervalSince(now))))
            } catch {
                return
            }
            currentDay = calendar.startOfDay(for: Date())
        }
    }
}
