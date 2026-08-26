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
    /// The routine the delete alert is about, by id — the list renders value structs, so the
    /// alert holds an identifier and resolves it when the user confirms.
    @State private var routinePendingDeletion: UUID?
    @State private var showingDeleteAlert = false
    @State private var showingActiveWorkout = false
#if DEBUG
    /// UI-test-only responsiveness measurement; inert without the launch argument.
    @StateObject private var stallProbe = MainThreadStallProbe()
#endif

    init(dependencies: AppDependencies) {
        self._viewModel = StateObject(wrappedValue: RoutinesViewModel(
            routineRepository: dependencies.routineRepository,
            workoutSessionRepository: dependencies.workoutSessionRepository,
            watchSync: dependencies.watchSync,
            proEntitlements: dependencies.proEntitlements,
            paywalls: dependencies.paywalls,
            proactivePaywalls: dependencies.proactivePaywalls
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
            activeWorkout: dependencies.activeWorkout,
            proactivePaywalls: dependencies.proactivePaywalls
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
                    if let id = routinePendingDeletion,
                       let routine = viewModel.routine(withId: id) {
                        viewModel.deleteRoutine(routine)
                    }
                    routinePendingDeletion = nil
                }
                Button("action.cancel".localized, role: .cancel) {
                    routinePendingDeletion = nil
                }
            } message: {
                Text("routine.delete.confirm".localized)
            }
        }
        // On the stack, not on its content: an alert bound to the root content
        // is not reliably presented once a destination is pushed over it, and
        // `RoutineDetailView` is where most edits are made.
        .routineSaveFailureAlert(viewModel)
        .onAppear {
            viewModel.fetchRoutines()
#if DEBUG
            stallProbe.reset()
#endif
        }
#if DEBUG
        .overlay(alignment: .bottomLeading) {
            MainThreadStallProbeOverlay(
                probe: stallProbe,
                identifier: "routines-main-thread-max-delay-ms"
            )
        }
#endif
    }

    // MARK: - List

    /// A single `LazyVStack` carrying the one-off leading content and the routine `ForEach`.
    ///
    /// Lazy because the plain `VStack` this replaces constructed and laid out every card the
    /// user owns — offscreen ones included — before the first frame (main-thread rule 1), and
    /// the routine count is unbounded for Pro users. Mixing the header, the hero and the
    /// section label into the same lazy stack is Apple's own documented shape; laziness only
    /// matters for the repeating content. The cards are precomputed value structs, which is
    /// the half that has to land *with* the laziness rather than after it — see
    /// docs/history-performance.md, where laziness alone made the History screen worse.
    private var routineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                header

                if let hero = viewModel.heroCard {
                    routineCard(hero, isHero: true)
                }

                if !viewModel.otherCards.isEmpty {
                    Text("routines.all".localized.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.7)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 4)
                        .padding(.top, 10)

                    ForEach(viewModel.otherCards) { card in
                        routineCard(card, isHero: false)
                    }
                }

                // Placement D — the non-blocking allowance hint, right next to
                // the affordance it explains. Nil for Pro, for Founders and
                // with the kill switch off.
                if let nudge = viewModel.routineCapNudge {
                    OnyxCapNudge(text: nudge.text, used: nudge.used, limit: nudge.limit)
                        .padding(.top, 2)
                }

                DashedCreateButton(title: "routines.new".localized) {
                    HapticManager.shared.light()
                    viewModel.requestAddRoutine()
                }
                // The gate is honest before the tap: at the cap the create tile
                // is marked as leading somewhere gated.
                .overlay(alignment: .trailing) {
                    if viewModel.isRoutineCapReached {
                        OnyxProBadge(style: .icon)
                            .padding(.trailing, 14)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, 2)

                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 16)
        }
    }

    /// The row holds a value struct and an id; the destructive and duplicating actions resolve
    /// that id back to the `@Model` in their closure, off the render path.
    private func routineCard(_ card: RoutineCardModel, isHero: Bool) -> some View {
        NavigationLink(value: card.id) {
            // `.equatable()` is what actually engages `RoutineCardView`'s `==`: SwiftUI
            // only consults a custom one through `EquatableView`, and the stored
            // `onStart` closure blocks the default structural comparison. Without it
            // every visible card re-evaluates its body on any republish of `otherCards`.
            RoutineCardView(
                card: card,
                isHero: isHero,
                onStart: { startWorkout(card.id) }
            )
            .equatable()
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
        .contextMenu {
            Button {
                if let routine = viewModel.routine(withId: card.id) {
                    viewModel.duplicateRoutine(routine)
                }
            } label: {
                Label("routine.duplicate".localized, systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                routinePendingDeletion = card.id
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
                viewModel.requestAddRoutine()
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
        String(
            format: "routines.header_meta".localized,
            viewModel.routines.count,
            TimeFormatting.lastTrainedLabel(for: viewModel.mostRecentTraining).lowercased()
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("routines.empty.title".localized, systemImage: "list.bullet.clipboard")
        } description: {
            Text("routines.empty.description".localized)
        } actions: {
            // Unreachable at the cap (the empty state means zero routines), but
            // routed through the same entry point so there is exactly one.
            Button("routines.add".localized) {
                viewModel.requestAddRoutine()
            }
            .buttonStyle(.onyxProminent)
        }
    }

    // MARK: - Actions

    private func startWorkout(_ routineId: UUID) {
        guard let routine = viewModel.routine(withId: routineId) else { return }
        HapticManager.shared.medium()
        workoutViewModel.startWorkout(routine: routine)
        showingActiveWorkout = true
    }
}

#Preview {
    RoutinesView()
        .modelContainer(PreviewModelContainer.shared)
}
