//
//  HistoryView.swift
//  GymStreak
//

import SwiftUI
import SwiftData

/// New top-level History tab replacing WorkoutHistoryView.
/// Hosts a segmented "Trainings / Fortschritt" control and drives navigation to detail views.
struct HistoryView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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

    private var sessions: [WorkoutSession] {
        viewModel.workoutHistory.filter { $0.endTime != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        segmented
                            .padding(.horizontal, 20)
                        if !viewModel.orphanedWatchWorkouts.isEmpty {
                            PendingSyncBannerView(orphans: viewModel.orphanedWatchWorkouts)
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                        }
                        Group {
                            switch section {
                            case .trainings:
                                TrainingsTabView(
                                    sessions: sessions,
                                    prExerciseCountBySession: prExerciseCountBySession,
                                    onDeleteRequested: requestDelete
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
                }
                .refreshable {
                    refresh()
                }
            }
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
            .onAppear {
                viewModel.updateModelContext(modelContext)
                refresh()
            }
            .onChange(of: viewModel.workoutHistory.count) {
                refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-run the HK reconciler when the user returns to the app —
                // catches workouts saved on the watch while iOS was backgrounded.
                if newPhase == .active {
                    Task { await viewModel.reconcileWatchWorkouts() }
                }
            }
            .alert("workout.history.delete.title".localized, isPresented: $showingDeleteAlert) {
                Button("action.delete".localized, role: .destructive) {
                    if let workout = workoutToDelete {
                        viewModel.deleteWorkout(workout)
                        workoutToDelete = nil
                        refresh()
                    }
                }
                Button("action.cancel".localized, role: .cancel) {
                    workoutToDelete = nil
                }
            } message: {
                Text("workout.history.delete.message".localized)
            }
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

    private func requestDelete(_ session: WorkoutSession) {
        workoutToDelete = session
        showingDeleteAlert = true
    }

    // MARK: - Data loading

    private func refresh() {
        let capturedSessions = sessions
        let prs = PersonalRecordService.computePRs(sessions: capturedSessions)
        prExerciseCountBySession = prs.prCountBySession
        fortschrittExercises = FortschrittAggregator.build(sessions: capturedSessions)
    }
}
