import SwiftUI

/// The active workout screen.
///
/// Redesign (2026-07-31): the exercise you are on is the only expanded card,
/// everything else collapses to a row; checking off a set and editing its
/// values are separate hit areas; values are edited in a keypad sheet instead
/// of an accordion that pushed the list around. All previously shipped
/// behaviour is preserved — supersets, swaps, progressive overload, body
/// weight, rest-timer config, HealthKit save and the recovery paths — only
/// where it lives on screen changed. See `docs/active-workout-redesign.md`.
struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingCancelAlert = false
    @State private var showingFinishConfirmation = false
    @State private var showingSaveOptions = false
    @State private var showingAddExercise = false
    @State private var showingRestTimerOverlay = false
    @State private var showingSwapLockedInfo = false

    @State private var exerciseToDelete: WorkoutExercise?
    @State private var exerciseToSwap: WorkoutExercise?
    @State private var pendingSetDeletion: PendingSetDeletion?
    @State private var valueEdit: SetValueEdit?
    @State private var overloadSheetExercise: WorkoutExercise?

    /// The exercise the user opened by hand. `nil` means "follow the workout" —
    /// the card tracks whichever exercise holds the next incomplete set.
    @State private var openedExerciseId: UUID?
    /// Per-exercise progressive-overload banner state, kept on the screen because
    /// only one card is mounted at a time and the state must survive switching.
    @State private var dismissedOverloadBanners: Set<UUID> = []
    @State private var appliedOverloads: [UUID: AppliedOverload] = [:]

    /// Equipment glyph per library exercise, cached so the avatars don't cost a
    /// routine-graph walk. `WorkoutExercise.exerciseId` always names what was
    /// actually performed (swaps rewrite it), so this needs no swap handling —
    /// and it only has to be rebuilt when the library itself changes.
    @State private var equipmentByExerciseId: [UUID: EquipmentType] = [:]

    /// Shared geometry namespace for the large↔compact rest-timer morph.
    @Namespace private var restTimerNamespace
    /// True while the morph animation is in flight — used to swallow rapid
    /// re-toggles, a known trigger for matchedGeometryEffect glitches.
    @State private var isRestTimerMorphing = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            if let session = viewModel.currentSession {
                // One pass over this workout's exercises resolves everything the
                // rows render, so no row body walks `setsList`, the routine slot
                // behind a swap, or the library exercise behind an equipment
                // icon. Bounded by a single workout (tens of sets), unlike the
                // history screen's unbounded lists.
                let data = WorkoutScreenData(
                    session: session,
                    viewModel: viewModel,
                    openedExerciseId: openedExerciseId,
                    equipmentByExerciseId: equipmentByExerciseId
                )
                content(session: session, data: data)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        WorkoutProgressHeader(
                            routineName: session.routineName,
                            elapsedTime: viewModel.elapsedTime,
                            completedSets: data.completedSets,
                            totalSets: data.totalSets,
                            segments: data.segments
                        )
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        footer(data: data)
                    }
                    .accessibilityHidden(showingRestTimerOverlay)
            }

            // The large timer is an in-tree overlay, not a sheet, so the shared
            // ring and time label can morph between it and the rest bar:
            // matchedGeometryEffect cannot cross a .sheet boundary.
            if showingRestTimerOverlay {
                ZStack {
                    DesignSystem.Colors.background
                        .ignoresSafeArea()
                    RestTimerView(
                        viewModel: viewModel,
                        namespace: restTimerNamespace,
                        onDismiss: { setRestTimerExpanded(false) }
                    )
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .tint(DesignSystem.Colors.textPrimary)
        .modifier(ActiveWorkoutAlerts(
            viewModel: viewModel,
            showingCancelAlert: $showingCancelAlert,
            showingFinishConfirmation: $showingFinishConfirmation,
            showingSaveOptions: $showingSaveOptions,
            showingSwapLockedInfo: $showingSwapLockedInfo,
            pendingSetDeletion: $pendingSetDeletion,
            onDismissWorkout: { dismiss() }
        ))
        .sheet(item: $exerciseToDelete) { exercise in
            DeleteExerciseConfirmationView(
                exercise: exercise,
                onConfirm: {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeExerciseFromWorkout(exercise)
                    }
                    exerciseToDelete = nil
                },
                onCancel: { exerciseToDelete = nil }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $exerciseToSwap) { exercise in
            SwapExercisePickerView(workoutExercise: exercise, viewModel: viewModel)
        }
        .sheet(item: $overloadSheetExercise) { exercise in
            WeightIncreaseSheet(
                workoutExercise: exercise,
                onApply: { increment in applyOverload(to: exercise, increment: increment) },
                onCancel: { overloadSheetExercise = nil }
            )
        }
        .sheet(item: $valueEdit) { edit in
            SetValueKeypadSheet(
                exerciseName: edit.exerciseName,
                setNumber: edit.display.number,
                field: edit.field,
                display: edit.display,
                canApplyToFollowing: edit.canApplyToFollowing,
                onSave: { reps, weight, applyToFollowing in
                    viewModel.updateSet(
                        edit.set,
                        in: edit.exercise,
                        reps: reps,
                        weight: weight,
                        // Only the field the sheet actually edited travels forward.
                        propagating: applyToFollowing ? edit.field : nil
                    )
                }
            )
            .presentationDetents([.height(edit.canApplyToFollowing ? 560 : 510)])
            .presentationDragIndicator(.visible)
            .presentationBackground(DesignSystem.Colors.background)
        }
        .sheet(isPresented: $showingSaveOptions) {
            SaveWorkoutView(viewModel: viewModel) { dismiss() }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseToWorkoutView(workoutViewModel: viewModel, exercisesViewModel: exercisesViewModel)
        }
        .onAppear { rebuildEquipmentLookup() }
        .onChange(of: exercisesViewModel.exercises.count) { _, _ in rebuildEquipmentLookup() }
        .onChange(of: viewModel.isRestTimerActive) { _, isActive in
            // Rest no longer takes over the screen — the bar is the default
            // surface and the large timer is opt-in. A stopped timer still
            // force-closes the overlay so it can never linger with no countdown.
            if !isActive {
                setRestTimerExpanded(false, force: true)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                viewModel.saveTimerState()
            case .active:
                viewModel.restoreTimerState()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - Content

    private func content(session: WorkoutSession, data: WorkoutScreenData) -> some View {
        ScrollViewReader { proxy in
            scrollContent(session: session, data: data)
                // Opening an exercise collapses the previous card above it, which
                // pulls several hundred points of content out from under the
                // viewport — without this the list appears to jump somewhere
                // unrelated instead of showing what was just tapped. Also covers
                // the automatic hand-off to the next exercise.
                // `initial: true` covers resuming a part-finished workout, where
                // the exercise to continue with can already be below the fold on
                // the very first frame — the same "nothing happened" symptom.
                .onChange(of: data.activeExerciseId, initial: true) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(DesignSystem.Animation.snappy) {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
        }
    }

    private func scrollContent(session: WorkoutSession, data: WorkoutScreenData) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if data.hasAssistanceExercise {
                    WorkoutBodyWeightCard(session: session, viewModel: viewModel)
                }

                ForEach(data.groups, id: \.first?.id) { group in
                    if group.count > 1, let first = group.first {
                        SupersetWorkoutGroupView(
                            exerciseCount: group.count,
                            supersetExercises: group,
                            letter: data.supersetLetter(for: first) ?? "A",
                            color: data.supersetColor(for: first),
                            viewModel: viewModel
                        ) {
                            ForEach(group, id: \.id) { exercise in
                                exerciseView(exercise, data: data)
                            }
                        }
                    } else if let exercise = group.first {
                        exerciseView(exercise, data: data)
                    }
                }

                addExerciseButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// One exercise, expanded or collapsed.
    ///
    /// The `.id(exercise.id)` sits on the *outer* `Group`, never on the two
    /// branches. Tagging both branches with the same explicit id tells SwiftUI
    /// they are one and the same view, and inside a `LazyVStack` that made it
    /// keep rendering the collapsed row after the state had already flipped —
    /// the tap registered, the haptic fired, and nothing expanded. With the id
    /// on the container, the branch swap is ordinary conditional content again
    /// and the id still serves as the `scrollTo` anchor.
    @ViewBuilder
    private func exerciseView(_ exercise: WorkoutExercise, data: WorkoutScreenData) -> some View {
        if let display = data.displays[exercise.id] {
            Group {
                if data.activeExerciseId == exercise.id {
                    expandedCard(exercise, display: display, data: data)
                } else {
                    WorkoutExerciseCollapsedRow(
                        display: display,
                        supersetBadge: data.supersetBadge(for: exercise),
                        onOpen: {
                            HapticManager.shared.light()
                            withAnimation(DesignSystem.Animation.snappy) {
                                openedExerciseId = exercise.id
                            }
                        }
                    )
                }
            }
            .id(exercise.id)
        }
    }

    private func expandedCard(
        _ exercise: WorkoutExercise,
        display: WorkoutExerciseDisplay,
        data: WorkoutScreenData
    ) -> some View {
        WorkoutExerciseCardView(
            display: display,
            supersetBadge: data.supersetBadge(for: exercise),
            banner: { overloadBanner(for: exercise, display: display) },
            setRows: { setRows(for: exercise, data: data) },
            onSwap: { exerciseToSwap = exercise },
            onSwapLockedInfo: { showingSwapLockedInfo = true },
            onRestTimeChange: { viewModel.updateRestTimeForExercise(exercise, restTime: $0) },
            onAddSet: {
                withAnimation(DesignSystem.Animation.spring) {
                    viewModel.addSetToExercise(exercise)
                }
            },
            onRemoveExercise: { exerciseToDelete = exercise }
        )
    }

    @ViewBuilder
    private func setRows(for exercise: WorkoutExercise, data: WorkoutScreenData) -> some View {
        let items = data.setItems[exercise.id] ?? []
        let nextId = items.first { !$0.display.isCompleted }?.id

        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            WorkoutSetRowView(
                display: item.display,
                isNext: item.id == nextId,
                onToggleCompleted: { toggleCompletion(of: item.set, in: exercise) },
                onEdit: { field in
                    valueEdit = SetValueEdit(
                        exercise: exercise,
                        set: item.set,
                        field: field,
                        display: item.display,
                        exerciseName: exercise.exerciseName,
                        // Nothing to propagate to when this is the last set still open.
                        canApplyToFollowing: items[(index + 1)...].contains { !$0.display.isCompleted }
                    )
                },
                onDuplicate: {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.duplicateSet(item.set, in: exercise)
                    }
                },
                onDelete: {
                    pendingSetDeletion = PendingSetDeletion(set: item.set, exercise: exercise)
                }
            )
        }
    }

    /// The rep-goal nudge and its confirmation, unchanged in behaviour — only
    /// its owner moved from the (now generic) card to the screen.
    @ViewBuilder
    private func overloadBanner(for exercise: WorkoutExercise, display: WorkoutExerciseDisplay) -> some View {
        if let applied = appliedOverloads[exercise.id] {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.success)

                Text("rep_range.routine_updated".localized(String(format: "%.1f", applied.weight), applied.reps))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Button {
                    withAnimation(DesignSystem.Animation.spring) {
                        appliedOverloads[exercise.id] = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("action.dismiss".localized)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.success.opacity(0.3), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if display.allCompletedSetsAtUpperLimit && !dismissedOverloadBanners.contains(exercise.id) {
            ProgressiveOverloadBanner(
                targetRepMax: display.targetRepMax ?? 0,
                isAssistance: display.isAssistance,
                onIncrease: { overloadSheetExercise = exercise },
                onDismiss: {
                    withAnimation(DesignSystem.Animation.spring) {
                        _ = dismissedOverloadBanners.insert(exercise.id)
                    }
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var addExerciseButton: some View {
        Button {
            HapticManager.shared.medium()
            showingAddExercise = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("workout.add_exercise".localized)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(DesignSystem.Colors.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(DesignSystem.Colors.tint.opacity(0.35))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityLabel("accessibility.add_exercise".localized)
        .accessibilityHint("accessibility.add_exercise.hint".localized)
    }

    // MARK: - Footer

    private func footer(data: WorkoutScreenData) -> some View {
        VStack(spacing: 8) {
            if viewModel.isRestTimerActive && !showingRestTimerOverlay {
                WorkoutRestBar(
                    remaining: viewModel.restTimeRemaining,
                    total: viewModel.restDuration,
                    namespace: restTimerNamespace,
                    onExpand: { setRestTimerExpanded(true) },
                    onExtend: { viewModel.extendRestTimer(by: 30) },
                    onSkip: { viewModel.stopRestTimer() }
                )
                .transition(.opacity)
            }

            WorkoutFooterActions(
                completedSets: data.completedSets,
                totalSets: data.totalSets,
                onCancel: { showingCancelAlert = true },
                onFinish: { showingFinishConfirmation = true }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        // Solid under the controls — a translucent footer let the scrolling list
        // show through the cancel button — with a short fade above it so the list
        // does not end on a hard edge.
        .background(DesignSystem.Colors.background)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [DesignSystem.Colors.background.opacity(0), DesignSystem.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .offset(y: -28)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Actions

    private func rebuildEquipmentLookup() {
        equipmentByExerciseId = Dictionary(
            exercisesViewModel.exercises.map { ($0.id, $0.equipmentType) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func toggleCompletion(of set: WorkoutSet, in exercise: WorkoutExercise) {
        if set.isCompleted {
            viewModel.uncompleteSet(set)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            // Correcting a set is a statement about *this* exercise — keep its
            // card open even if the workout's next set lives elsewhere.
            openedExerciseId = exercise.id
        } else {
            viewModel.completeSet(workoutExercise: exercise, set: set)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(DesignSystem.Animation.snappy) {
                if exercise.isInSuperset || exercise.setsList.allSatisfy(\.isCompleted) {
                    // Hand navigation back to `findNextIncompleteSet()`. It is the
                    // only thing that knows a superset's round order (A1 → B1 → A2
                    // → B2), and `completeSet` deliberately delegates that to the
                    // view — so pinning the card to the exercise just logged would
                    // strand the user on A while B is the actual next move.
                    openedExerciseId = nil
                } else {
                    // Standalone exercise with sets left: stay put. Clearing here
                    // would yank a user who deliberately jumped ahead (busy rack)
                    // back to the workout's first incomplete exercise after every
                    // single set.
                    openedExerciseId = exercise.id
                }
            }
        }
    }

    private func applyOverload(to exercise: WorkoutExercise, increment: Double) {
        // Compute the confirmation values from the performed weight BEFORE
        // applying — apply rewrites the actual values.
        let currentWeight = exercise.setsList.sorted { $0.order < $1.order }.first?.actualWeight ?? 0
        let newWeight = ProgressiveOverloadService.increasedWeight(
            currentWeight,
            increment: increment,
            loadBehavior: exercise.loadBehavior
        )
        let minReps = exercise.targetRepMin ?? 0
        viewModel.applyProgressiveOverload(for: exercise, weightIncrement: increment)
        overloadSheetExercise = nil
        withAnimation(DesignSystem.Animation.spring) {
            _ = dismissedOverloadBanners.insert(exercise.id)
            appliedOverloads[exercise.id] = AppliedOverload(weight: newWeight, reps: minReps)
        }
    }

    /// Switches between the large rest-timer overlay and the bar in a single
    /// animated transaction, so exactly one variant is mounted at a time and the
    /// shared ring/label morph between them.
    ///
    /// Taps arriving while a morph is in flight are ignored — rapid re-toggling
    /// of `matchedGeometryEffect` is a known source of ghosting and
    /// AttributeGraph glitches. Pass `force` for state-driven closes that must
    /// never be dropped.
    private func setRestTimerExpanded(_ expanded: Bool, force: Bool = false) {
        guard showingRestTimerOverlay != expanded else { return }
        guard force || !isRestTimerMorphing else { return }

        isRestTimerMorphing = true
        withAnimation(RestTimerMorph.animation) {
            showingRestTimerOverlay = expanded
        } completion: {
            isRestTimerMorphing = false
        }
    }

    // MARK: - Screen state

    private struct AppliedOverload {
        let weight: Double
        let reps: Int
    }

    /// `fileprivate` so `ActiveWorkoutAlerts` below can bind to it.
    fileprivate struct PendingSetDeletion: Identifiable {
        let set: WorkoutSet
        let exercise: WorkoutExercise
        // `self.` is required: a bare `set` here parses as the setter keyword.
        var id: UUID { self.set.id }
    }

    private struct SetValueEdit: Identifiable {
        let exercise: WorkoutExercise
        let set: WorkoutSet
        let field: WorkoutSetField
        let display: WorkoutSetDisplay
        let exerciseName: String
        let canApplyToFollowing: Bool
        var id: String { "\(set.id)-\(field)" }
    }

    /// Everything the screen renders, resolved in one pass per body evaluation.
    /// `@MainActor` because it reads the view model while building.
    @MainActor
    private struct WorkoutScreenData {
        let groups: [[WorkoutExercise]]
        let displays: [UUID: WorkoutExerciseDisplay]
        /// Only the open exercise has rows — the collapsed ones render none.
        let setItems: [UUID: [WorkoutSetRowItem]]
        let segments: [[Bool]]
        let completedSets: Int
        let totalSets: Int
        let hasAssistanceExercise: Bool
        let activeExerciseId: UUID?
        private let supersetLetters: [UUID: String]

        init(
            session: WorkoutSession,
            viewModel: WorkoutViewModel,
            openedExerciseId: UUID?,
            equipmentByExerciseId: [UUID: EquipmentType]
        ) {
            let ordered = session.workoutExercisesList.sorted { $0.order < $1.order }
            groups = session.exercisesGroupedBySupersets
            supersetLetters = SupersetLabelProvider.labels(for: ordered)

            // The card follows the workout unless the user opened one by hand —
            // and a hand-opened exercise that has since been removed falls back
            // to the workout's own next set rather than leaving nothing open.
            let active: UUID?
            if let openedExerciseId, ordered.contains(where: { $0.id == openedExerciseId }) {
                active = openedExerciseId
            } else {
                active = viewModel.findNextIncompleteSet()?.exercise.id ?? ordered.first?.id
            }
            activeExerciseId = active

            var displays: [UUID: WorkoutExerciseDisplay] = [:]
            var setItems: [UUID: [WorkoutSetRowItem]] = [:]
            var segments: [[Bool]] = []
            var completed = 0
            var total = 0
            var hasAssistance = false

            for exercise in ordered {
                let sets = exercise.setsList.sorted { $0.order < $1.order }
                let isAssistance = exercise.loadBehavior.isCounterweightAssistance
                hasAssistance = hasAssistance || isAssistance
                let isActive = exercise.id == active

                // Only the open card renders set rows, so only it pays for them.
                if isActive {
                    setItems[exercise.id] = sets.enumerated().map { index, set in
                        WorkoutSetRowItem(
                            set: set,
                            display: WorkoutSetDisplay(
                                id: set.id,
                                number: index + 1,
                                reps: set.actualReps,
                                weight: set.actualWeight,
                                plannedReps: set.plannedReps,
                                plannedWeight: set.plannedWeight,
                                isCompleted: set.isCompleted,
                                completedAt: set.completedAt,
                                isAssistance: isAssistance,
                                targetRepMin: exercise.targetRepMin,
                                targetRepMax: exercise.targetRepMax
                            )
                        )
                    }
                }

                let completedInExercise = sets.filter(\.isCompleted).count

                // `canSwap`/`swapTargets` traverse the routine graph (slot →
                // alternatives → their sets), so they are resolved only for the
                // card that can actually show the affordance.
                var canSwap = false
                var isSwapLocked = false
                if isActive {
                    canSwap = viewModel.canSwap(exercise)
                    isSwapLocked = !canSwap
                        && completedInExercise > 0
                        && !viewModel.swapTargets(for: exercise).isEmpty
                }

                displays[exercise.id] = WorkoutExerciseDisplay(
                    id: exercise.id,
                    name: exercise.exerciseName,
                    muscleGroups: exercise.muscleGroups,
                    equipmentType: exercise.exerciseId.flatMap { equipmentByExerciseId[$0] } ?? .dumbbell,
                    completedSets: completedInExercise,
                    totalSets: sets.count,
                    leadWeight: sets.first?.actualWeight ?? 0,
                    isAssistance: isAssistance,
                    restTime: sets.first?.restTime ?? 0,
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    swappedFromName: exercise.wasSwapped ? exercise.plannedExerciseName : nil,
                    canSwap: canSwap,
                    isSwapLocked: isSwapLocked,
                    isInSuperset: exercise.isInSuperset,
                    // Computed from the already-materialised `sets` rather than
                    // the model's own property, which would walk `setsList` again.
                    allCompletedSetsAtUpperLimit: ProgressiveOverloadService.workoutQualifiesForIncrease(
                        sets: sets.map { .init(reps: $0.actualReps, isCompleted: $0.isCompleted) },
                        targetRepMax: exercise.targetRepMax,
                        overloadAlreadyApplied: exercise.progressiveOverloadApplied
                    )
                )

                segments.append(sets.map(\.isCompleted))
                completed += completedInExercise
                total += sets.count
            }

            self.displays = displays
            self.setItems = setItems
            self.segments = segments
            completedSets = completed
            totalSets = total
            hasAssistanceExercise = hasAssistance
        }

        func supersetLetter(for exercise: WorkoutExercise) -> String? {
            guard let supersetId = exercise.supersetId else { return nil }
            return supersetLetters[supersetId]
        }

        func supersetColor(for exercise: WorkoutExercise) -> Color {
            SupersetLabelProvider.color(for: supersetLetter(for: exercise) ?? "A")
        }

        func supersetBadge(for exercise: WorkoutExercise) -> (position: Int, total: Int, color: Color)? {
            guard exercise.isInSuperset,
                  let group = groups.first(where: { $0.contains { $0.id == exercise.id } }),
                  group.count > 1,
                  let index = group.firstIndex(where: { $0.id == exercise.id }) else { return nil }
            return (index + 1, group.count, supersetColor(for: exercise))
        }
    }
}

// MARK: - Alerts

/// The workout's confirmations, lifted out of the screen body so the view stays
/// readable. Behaviour is unchanged from before the redesign.
private struct ActiveWorkoutAlerts: ViewModifier {
    @ObservedObject var viewModel: WorkoutViewModel
    @Binding var showingCancelAlert: Bool
    @Binding var showingFinishConfirmation: Bool
    @Binding var showingSaveOptions: Bool
    @Binding var showingSwapLockedInfo: Bool
    @Binding var pendingSetDeletion: ActiveWorkoutView.PendingSetDeletion?
    let onDismissWorkout: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("workout.cancel.title".localized, isPresented: $showingCancelAlert) {
                Button("workout.cancel.discard".localized, role: .destructive) {
                    viewModel.cancelWorkout()
                    onDismissWorkout()
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
            .alert("workout.swap.locked.title".localized, isPresented: $showingSwapLockedInfo) {
                Button("action.done".localized, role: .cancel) {}
            } message: {
                Text("workout.swap.locked.message".localized)
            }
            .alert(
                "set.delete.title".localized,
                isPresented: Binding(
                    get: { pendingSetDeletion != nil },
                    set: { if !$0 { pendingSetDeletion = nil } }
                ),
                presenting: pendingSetDeletion
            ) { deletion in
                Button("set.delete.confirm".localized, role: .destructive) {
                    withAnimation(DesignSystem.Animation.spring) {
                        viewModel.removeSetFromExercise(deletion.set, from: deletion.exercise)
                    }
                    pendingSetDeletion = nil
                }
                Button("action.cancel".localized, role: .cancel) {
                    pendingSetDeletion = nil
                }
            } message: { _ in
                Text("set.delete.message".localized)
            }
    }
}

// MARK: - Body weight

/// Only shown when the workout contains a counterweight-assistance exercise:
/// the actual load moved is body mass minus assistance, so the session needs
/// the user's body weight to compute it.
private struct WorkoutBodyWeightCard: View {
    let session: WorkoutSession
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var bodyWeight: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("exercise.body_weight".localized)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("exercise.body_weight.detail".localized)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            WeightInput(title: "exercise.body_weight.input".localized, weight: $bodyWeight) { value in
                viewModel.updateBodyWeight(value > 0 ? value : nil)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { bodyWeight = session.bodyWeightKg ?? 0 }
    }
}

// MARK: - Delete Exercise Confirmation View

struct DeleteExerciseConfirmationView: View {
    let exercise: WorkoutExercise
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 8)

            Image(systemName: "trash.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignSystem.Colors.destructive)
                .symbolRenderingMode(.hierarchical)

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

            VStack(spacing: 12) {
                Button(role: .destructive, action: onConfirm) {
                    Text("delete_exercise.remove".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.destructive)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onCancel) {
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

/// Groups the exercises of one superset and owns the round's rest time — a
/// superset rests once per round, not once per exercise, so the control cannot
/// live on the individual cards.
struct SupersetWorkoutGroupView<Content: View>: View {
    let exerciseCount: Int
    let supersetExercises: [WorkoutExercise]
    let letter: String
    let color: Color
    @ObservedObject var viewModel: WorkoutViewModel
    let content: Content
    @State private var showingRestTimeConfig = false

    /// Rest comes off the last exercise's first set, because rest triggers after
    /// the last exercise in a round.
    private var supersetRestTime: TimeInterval {
        guard let lastExercise = supersetExercises.sorted(by: { $0.supersetOrder < $1.supersetOrder }).last,
              let firstSet = lastExercise.setsList.sorted(by: { $0.order < $1.order }).first else {
            return 60.0
        }
        return firstSet.restTime
    }

    init(
        exerciseCount: Int,
        supersetExercises: [WorkoutExercise],
        letter: String,
        color: Color,
        viewModel: WorkoutViewModel,
        @ViewBuilder content: () -> Content
    ) {
        self.exerciseCount = exerciseCount
        self.supersetExercises = supersetExercises
        self.letter = letter
        self.color = color
        self.viewModel = viewModel
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                Text("superset.label".localized(letter))
                    .font(.caption.weight(.semibold))
                Text("superset.exercise_count".localized(exerciseCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if supersetRestTime > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text(TimeFormatting.formatRestTime(supersetRestTime))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(color)
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.15)))
            .padding(.bottom, 8)

            SupersetRestTimerConfig(
                restTime: Binding(
                    get: { supersetRestTime },
                    set: { updateRoundRestTime($0) }
                ),
                isExpanded: $showingRestTimeConfig,
                onRestTimeChange: { updateRoundRestTime($0) }
            )
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.leading, 4)

                VStack(spacing: 10) {
                    content
                }
                .padding(.leading, 12)
            }
        }
        .padding(12)
        .background(color.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func updateRoundRestTime(_ newValue: TimeInterval) {
        guard let lastExercise = supersetExercises.sorted(by: { $0.supersetOrder < $1.supersetOrder }).last else { return }
        viewModel.updateRestTimeForExercise(lastExercise, restTime: newValue)
    }
}
