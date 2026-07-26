//
//  HistoryView.swift
//  GymStreak
//

import SwiftUI
import SwiftData

/// Stack destination for the AI Coach settings screen.
private struct AICoachSettingsDestination: Hashable {}

/// New top-level History tab replacing WorkoutHistoryView.
/// Hosts a segmented "Trainings / Fortschritt" control and drives navigation to detail views.
struct HistoryView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    /// Live routines (with their schedules) drive the dynamic weekly goal.
    @Query private var routines: [Routine]

    enum Section: String, CaseIterable {
        case trainings, fortschritt

        var title: String {
            switch self {
            case .trainings:    return "history.mode.workouts".localized
            case .fortschritt:  return "history.mode.progress".localized
            }
        }
    }

    @State private var section: Section = .trainings
    @State private var fortschrittExercises: [FortschrittExerciseModel] = []
    @State private var prExerciseCountBySession: [UUID: Int] = [:]
    @State private var workoutToDelete: WorkoutSession?
    @State private var showingDeleteAlert = false
    @State private var isRecovering = false
    /// Swipe-to-delete state for the Trainings list cards. Owned here because
    /// this view owns the scroll view that has to close an open card.
    @State private var swipeState = HistorySwipeState()
    /// Backs the stack so the swipeable list cards can push programmatically.
    /// Type-erased on purpose: the same stack also pushes `ExerciseWithHistory`
    /// and `PeriodRecapDestination` values from other links.
    @State private var path = NavigationPath()

    private var sessions: [WorkoutSession] {
        viewModel.workoutHistory.filter { $0.endTime != nil }
    }

    /// Stable signature of the live Exercise library — flips whenever a user adds, removes,
    /// or renames an exercise. Used to retrigger the Fortschritt aggregator so the list never
    /// shows entries for exercises the user has since deleted.
    private var exerciseLibrarySignature: [String] {
        allExercises.map { "\($0.id.uuidString):\($0.name)" }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        segmented
                            .padding(.horizontal, 20)
                        if !viewModel.orphanedWatchWorkouts.isEmpty {
                            PendingSyncBannerView(orphans: viewModel.orphanedWatchWorkouts) {
                                isRecovering = true
                                Task {
                                    await viewModel.recoverOrphanedWorkouts()
                                    isRecovering = false
                                    refresh()
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
                                    sessions: sessions,
                                    routines: routines,
                                    prExerciseCountBySession: prExerciseCountBySession,
                                    onDeleteRequested: requestDelete,
                                    onSelectWorkout: pushWorkout,
                                    swipeState: $swipeState
                                )
                            case .fortschritt:
                                FortschrittTabView(
                                    exercises: fortschrittExercises,
                                    allExerciseNames: fortschrittExercises.map(\.name)
                                )
                            }
                        }
                        .padding(.top, 4)

                        Color.clear.frame(height: 60)
                    }
                    .animation(.easeInOut(duration: 0.25), value: viewModel.healthKitDeleteFailed)
                }
                .refreshable {
                    refresh()
                }
                // Scrolling closes an open swipe card, the way a List does.
                // Suppressed mid-drag so a slightly diagonal swipe cannot close
                // the card it is opening.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { oldValue, newValue in
                    guard oldValue != newValue,
                          swipeState.openCardId != nil,
                          swipeState.draggingCardId == nil else { return }
                    withAnimation(DesignSystem.Animation.spring) {
                        swipeState.openCardId = nil
                    }
                }
            }
            // Keep the tab root free of navigation chrome without passing that
            // preference to its pushed destinations.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { sessionId in
                if let session = sessions.first(where: { $0.id == sessionId }) {
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
                viewModel.fetchWorkoutHistory()
                Task { await viewModel.reconcileWatchWorkouts() }
                refresh()
            }
            .onChange(of: viewModel.workoutHistory.count) {
                refresh()
            }
            .onChange(of: exerciseLibrarySignature) {
                refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-run the HK reconciler when the user returns to the app —
                // catches workouts saved on the watch while iOS was backgrounded.
                if newPhase == .active {
                    Task { await viewModel.reconcileWatchWorkouts() }
                }
            }
            .deleteWorkoutConfirmation(
                isPresented: $showingDeleteAlert,
                hasHealthKitWorkout: workoutToDelete?.healthKitWorkoutId != nil,
                onDelete: { alsoFromHealthKit in
                    if let workout = workoutToDelete {
                        viewModel.deleteWorkout(workout, alsoFromHealthKit: alsoFromHealthKit)
                        workoutToDelete = nil
                        refresh()
                        HapticManager.shared.success()
                    }
                },
                onCancel: { workoutToDelete = nil }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("history.title".localized)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .kerning(-0.7)
                .foregroundStyle(Color.white)

            Spacer()

            Button {
                path.append(AICoachSettingsDestination())
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ai_coach.settings.open".localized)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Segmented

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases, id: \.self) { target in
                Button {
                    HapticManager.shared.selection()
                    swipeState.openCardId = nil
                    withAnimation(.easeOut(duration: 0.18)) { section = target }
                } label: {
                    Text(target.title)
                        .font(.system(size: 15, weight: section == target ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(section == target ? Color.white : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            section == target ? Color.white.opacity(0.12) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Actions

    /// Pushes a workout detail screen for a list card.
    ///
    /// A `NavigationLink` could not fire twice; a programmatic push can, so a fast
    /// double tap is ignored. Cards are only tappable at the root of the stack.
    private func pushWorkout(_ sessionId: UUID) {
        guard path.isEmpty else { return }
        path.append(sessionId)
    }

    private func requestDelete(_ session: WorkoutSession) {
        workoutToDelete = session
        showingDeleteAlert = true
    }

    // MARK: - Data loading

    private func refresh() {
        let capturedSessions = sessions
        let liveExercises = allExercises
        let prs = PersonalRecordService.computePRs(sessions: capturedSessions)
        prExerciseCountBySession = prs.prCountBySession
        fortschrittExercises = FortschrittAggregator.build(
            sessions: capturedSessions,
            liveExercises: liveExercises
        )
    }
}
