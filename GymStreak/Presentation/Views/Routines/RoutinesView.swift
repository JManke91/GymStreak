import SwiftUI
import SwiftData

struct RoutinesView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        RoutinesViewInternal(dependencies: dependencies)
    }
}

private struct RoutinesViewInternal: View {
    @StateObject private var viewModel: RoutinesViewModel
    @StateObject private var exercisesViewModel: ExercisesViewModel
    @StateObject private var workoutViewModel: WorkoutViewModel
    @State private var routinePendingDeletion: Routine?
    @State private var showingDeleteAlert = false
    @State private var showingActiveWorkout = false

    init(dependencies: AppDependencies) {
        self._viewModel = StateObject(wrappedValue: RoutinesViewModel(
            routineRepository: dependencies.routineRepository,
            workoutSessionRepository: dependencies.workoutSessionRepository,
            watchSync: dependencies.watchSync
        ))
        self._exercisesViewModel = StateObject(wrappedValue: ExercisesViewModel(
            exerciseRepository: dependencies.exerciseRepository,
            routineRepository: dependencies.routineRepository,
            catalogSync: dependencies.exerciseCatalogSync
        ))
        self._workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(
            workoutSessionRepository: dependencies.workoutSessionRepository,
            routineRepository: dependencies.routineRepository,
            healthKitManager: dependencies.makeHealthKitWorkoutService(),
            watchSync: dependencies.watchSync,
            workoutHistoryCorrelation: dependencies.workoutHistoryCorrelation,
            restTimerReminders: dependencies.restTimerReminders,
            restTimerLiveActivity: dependencies.restTimerLiveActivity,
            routineTemplateSync: dependencies.routineTemplateSync,
            recovery: dependencies.workoutRecovery,
            activeWorkout: dependencies.activeWorkout
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                if viewModel.routines.isEmpty {
                    emptyState
                } else {
                    routineList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { routineId in
                if let routine = viewModel.routines.first(where: { $0.id == routineId }) {
                    RoutineDetailView(
                        routine: routine,
                        viewModel: viewModel,
                        exercisesViewModel: exercisesViewModel,
                        workoutViewModel: workoutViewModel
                    )
                }
            }
            .fullScreenCover(isPresented: $viewModel.showingAddRoutine) {
                NavigationStack {
                    CreateRoutineView(
                        routinesViewModel: viewModel,
                        exercisesViewModel: exercisesViewModel
                    )
                }
            }
            .fullScreenCover(isPresented: $showingActiveWorkout) {
                ActiveWorkoutView(viewModel: workoutViewModel, exercisesViewModel: exercisesViewModel)
            }
            .alert("routine.delete".localized, isPresented: $showingDeleteAlert) {
                Button("action.delete".localized, role: .destructive) {
                    if let routine = routinePendingDeletion {
                        viewModel.deleteRoutine(routine)
                        routinePendingDeletion = nil
                    }
                }
                Button("action.cancel".localized, role: .cancel) {
                    routinePendingDeletion = nil
                }
            } message: {
                Text("routine.delete.confirm".localized)
            }
        }
        .onAppear {
            viewModel.fetchRoutines()
        }
    }

    // MARK: - List

    private var routineList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                if let hero = viewModel.upNextRoutine {
                    routineCard(hero, isHero: true)

                    let rest = viewModel.routines.filter { $0.id != hero.id }
                    if !rest.isEmpty {
                        Text("routines.all".localized.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .kerning(0.7)
                            .foregroundStyle(Color.white.opacity(0.45))
                            .padding(.horizontal, 4)
                            .padding(.top, 10)

                        ForEach(rest) { routine in
                            routineCard(routine, isHero: false)
                        }
                    }
                }

                DashedCreateButton(title: "routines.new".localized) {
                    HapticManager.shared.light()
                    viewModel.showingAddRoutine = true
                }
                .padding(.top, 2)

                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 16)
        }
    }

    private func routineCard(_ routine: Routine, isHero: Bool) -> some View {
        NavigationLink(value: routine.id) {
            RoutineCardView(
                routine: routine,
                lastPerformed: viewModel.lastPerformedByRoutine[routine.id],
                isHero: isHero,
                onStart: { startWorkout(routine) }
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
        .contextMenu {
            Button {
                viewModel.duplicateRoutine(routine)
            } label: {
                Label("routine.duplicate".localized, systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                routinePendingDeletion = routine
                showingDeleteAlert = true
            } label: {
                Label("routine.delete".localized, systemImage: "trash")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("routines.title".localized)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .kerning(-0.7)
                    .foregroundStyle(.white)
                Text(headerSubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            Button {
                HapticManager.shared.light()
                viewModel.showingAddRoutine = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 38, height: 38)
                    .background(DesignSystem.Colors.tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("routines.add".localized)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var headerSubtitle: String {
        let mostRecent = viewModel.lastPerformedByRoutine.values.max()
        return String(
            format: "routines.header_meta".localized,
            viewModel.routines.count,
            TimeFormatting.lastTrainedLabel(for: mostRecent).lowercased()
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("routines.empty.title".localized, systemImage: "list.bullet.clipboard")
        } description: {
            Text("routines.empty.description".localized)
        } actions: {
            Button("routines.add".localized) {
                viewModel.showingAddRoutine = true
            }
            .buttonStyle(.onyxProminent)
        }
    }

    // MARK: - Actions

    private func startWorkout(_ routine: Routine) {
        HapticManager.shared.medium()
        workoutViewModel.startWorkout(routine: routine)
        showingActiveWorkout = true
    }
}

#Preview {
    RoutinesView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self], inMemory: true)
}
