import SwiftUI

/// Routine detail (redesign v2): a scroll of self-contained exercise cards.
/// Every card carries a parameter chip strip whose editors open in place, and
/// expands into an always-editable set list plus its alternatives. A separate
/// "Sortieren" mode swaps the cards for compact drag rows.
struct RoutineDetailView: View {
    @Bindable var routine: Routine
    @ObservedObject var viewModel: RoutinesViewModel
    @ObservedObject var exercisesViewModel: ExercisesViewModel
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    // Sheets & alerts
    @State private var showingAddExercise = false
    @State private var showingDeleteAlert = false
    @State private var showingActiveWorkout = false
    @State private var showingRenameAlert = false
    @State private var renameText: String = ""
    @State private var showingSchedulePlanner = false
    @State private var addAlternativeTarget: RoutineExercise?
    @State private var selectedExerciseForOverload: RoutineExercise?

    // Card state
    @State private var expandedExerciseId: UUID?
    @State private var expandedAlternativeId: UUID?
    /// Which chip editor is open per exercise card.
    @State private var openParameters: [UUID: ExerciseCardParameter] = [:]
    @State private var overloadBannerDismissedForExercise: [UUID: Bool] = [:]
    @State private var scrollToExerciseId: UUID?
    /// One shared "a set value is being typed" flag drives the keyboard Done bar.
    @FocusState private var isEditingSetValue: Bool

    // Sorting mode
    @State private var isSorting: Bool = false
    @State private var removedExercise: RemovedRoutineExerciseSnapshot?
    @State private var undoDismissTask: Task<Void, Never>?

    // Shared with RoutineDetailView+Supersets (extensions can't see private state)
    @State var supersetEditMode: SupersetEditMode?
    @State var supersetEditSelection: Set<UUID> = []

    // MARK: - Shared helpers

    func restTime(for exercise: RoutineExercise) -> TimeInterval {
        exercise.setsList.first?.restTime ?? 0.0
    }

    func updateAllSetsRestTime(for routineExercise: RoutineExercise, restTime: TimeInterval) {
        viewModel.updateRestTime(restTime, for: routineExercise)
    }

    /// Collapses every per-card editing state (used when entering a mode that
    /// takes over the list).
    func collapseCardState() {
        expandedExerciseId = nil
        expandedAlternativeId = nil
        openParameters = [:]
    }

    // MARK: - Alternatives doorway

    /// Expands the card with its first alternative open; with none yet, jumps
    /// straight into the add-alternative picker.
    func openAlternatives(for routineExercise: RoutineExercise) {
        guard !isSorting, supersetEditMode == nil else { return }
        withAnimation(DesignSystem.Animation.spring) {
            collapseCardState()
            expandedExerciseId = routineExercise.id
            expandedAlternativeId = routineExercise.alternativesList.first?.id
        }
        if !routineExercise.hasAlternatives {
            addAlternativeTarget = routineExercise
        }
        scrollToExerciseId = routineExercise.id
        HapticManager.shared.medium()
    }

    // MARK: - Removal with undo

    /// Removes immediately and offers an undo toast (the design replaced the
    /// confirmation alert with this).
    func removeExercise(_ routineExercise: RoutineExercise) {
        if expandedExerciseId == routineExercise.id { collapseCardState() }
        let snapshot = withAnimation(DesignSystem.Animation.spring) {
            viewModel.removeRoutineExercise(routineExercise, from: routine)
        }
        guard let snapshot else { return }
        HapticManager.shared.medium()
        withAnimation(DesignSystem.Animation.spring) {
            removedExercise = snapshot
            // Sorting mode has no empty state and its Fertig button is hidden
            // for an empty routine — removing the last exercise while sorting
            // would otherwise leave no way out but the back button.
            if routine.routineExercisesList.isEmpty { isSorting = false }
        }
        scheduleUndoDismissal()
    }

    private func scheduleUndoDismissal() {
        undoDismissTask?.cancel()
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(DesignSystem.Animation.spring) {
                removedExercise = nil
            }
        }
    }

    private func undoRemoval() {
        guard let snapshot = removedExercise else { return }
        undoDismissTask?.cancel()
        withAnimation(DesignSystem.Animation.spring) {
            viewModel.restoreRoutineExercise(snapshot, in: routine)
            removedExercise = nil
        }
    }

    // MARK: - Body

    var sortedExercises: [RoutineExercise] {
        routine.routineExercisesList.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            if isSorting {
                sortingModeContent
            } else {
                browsingModeContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        // ToolbarItemGroup(placement: .keyboard) does not render on iOS 26
        // (see docs/routines-exercises-redesign.md) — the Done bar rides on a
        // safeAreaInset instead.
        .keyboardDoneBar(isFocused: $isEditingSetValue)
        .safeAreaInset(edge: .bottom) {
            bottomInset
        }
        .overlay(alignment: .bottom) {
            undoToastOverlay
        }
        .sheet(isPresented: $showingAddExercise) {
            RoutineExercisePickerView(
                alreadyAddedExercises: routine.routineExercisesList.compactMap(\.exercise),
                exercisesViewModel: exercisesViewModel,
                routineName: routine.name,
                onExerciseConfigured: { exercise, sets, alternatives, repMin, repMax in
                    viewModel.addConfiguredExercise(
                        exercise,
                        to: routine,
                        sets: sets,
                        alternatives: alternatives,
                        targetRepMin: repMin,
                        targetRepMax: repMax
                    )
                }
            )
        }
        .sheet(isPresented: $showingSchedulePlanner) {
            SchedulePlanningSheet(routine: routine, viewModel: viewModel)
        }
        .sheet(item: $addAlternativeTarget) { target in
            AddAlternativeView(
                routineExercise: target,
                viewModel: viewModel,
                // Open the new alternative's editor so its sets can be defined
                // right away.
                onAdded: { expandedAlternativeId = $0.id }
            )
        }
        .sheet(item: $selectedExerciseForOverload) { exercise in
            WeightIncreaseSheet(
                routineExercise: exercise,
                onApply: { increment in
                    viewModel.applyProgressiveOverload(for: exercise, weightIncrement: increment)
                    selectedExerciseForOverload = nil
                    overloadBannerDismissedForExercise[exercise.id] = true
                },
                onCancel: {
                    selectedExerciseForOverload = nil
                }
            )
        }
        .alert("routine.rename".localized, isPresented: $showingRenameAlert) {
            TextField("add_routine.name_placeholder".localized, text: $renameText)
            Button("action.save".localized) {
                let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty && trimmedName != routine.name {
                    routine.name = trimmedName
                    viewModel.updateRoutine(routine)
                }
            }
            Button("action.cancel".localized, role: .cancel) {}
        }
        .alert("routine.delete".localized, isPresented: $showingDeleteAlert) {
            Button("action.delete".localized, role: .destructive) {
                viewModel.deleteRoutine(routine)
                dismiss()
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("routine.delete.confirm".localized)
        }
        .fullScreenCover(isPresented: $showingActiveWorkout) {
            ActiveWorkoutView(viewModel: workoutViewModel, exercisesViewModel: exercisesViewModel)
        }
        .onAppear {
            // Routines stored before supersets had to be contiguous (or edited
            // on the watch) can hold scattered members — pull them back into
            // their blocks before the first read of `sortedExercises` matters.
            viewModel.normalizeSupersetOrdering(in: routine)
        }
        .onDisappear {
            undoDismissTask?.cancel()
        }
    }

    /// Normal mode: ScrollView + LazyVStack (deliberately NOT List). List snaps
    /// intra-row height changes, so expanding a card or its set list would read
    /// as a re-render instead of growth.
    private var browsingModeContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    topBar
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if supersetEditMode == nil {
                        RoutineScheduleCard(
                            schedule: routine.schedule,
                            nextDue: viewModel.nextDueDate(for: routine),
                            onTap: {
                                HapticManager.shared.light()
                                showingSchedulePlanner = true
                            }
                        )
                        .padding(.bottom, 10)
                    }

                    if routine.routineExercisesList.isEmpty {
                        emptyState
                    } else {
                        exerciseRows
                    }

                    if !routine.routineExercisesList.isEmpty && supersetEditMode == nil {
                        DashedCreateButton(title: "routine.add_exercise".localized) {
                            showingAddExercise = true
                        }
                        .padding(.top, 6)
                    }

                    Color.clear
                        .frame(height: 40)
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: scrollToExerciseId) { _, newValue in
                guard let id = newValue else { return }
                withAnimation(DesignSystem.Animation.spring) {
                    proxy.scrollTo(id, anchor: .top)
                }
                scrollToExerciseId = nil
            }
        }
    }

    // MARK: - Top bar & title

    // Shared with the sorting container (extensions cannot see private members).
    var topBar: some View {
        HStack(spacing: 8) {
            Button {
                HapticManager.shared.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("action.back".localized)

            Spacer()

            if supersetEditMode == nil && (!routine.routineExercisesList.isEmpty || isSorting) {
                Button {
                    toggleSortingMode()
                } label: {
                    Text(isSorting ? "action.done".localized : "routine.sort".localized)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(isSorting ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.tint)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(isSorting ? DesignSystem.Colors.tint : DesignSystem.Colors.tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if supersetEditMode == nil {
                Menu {
                    Button {
                        renameText = routine.name
                        showingRenameAlert = true
                    } label: {
                        Label("routine.rename".localized, systemImage: "pencil")
                    }
                    Button {
                        HapticManager.shared.success()
                        viewModel.duplicateRoutine(routine)
                    } label: {
                        Label("routine.duplicate".localized, systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("routine.delete".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routine.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.6)
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RoutineMetricsService.primaryMuscleGroups(for: routine), id: \.self) { muscle in
                        MuscleChipView(muscleGroup: muscle)
                    }
                    Text(metaText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.leading, 4)
                }
            }

            if let editMode = supersetEditMode {
                Text(editMode == .creating ? "superset.create_new".localized : "superset.edit".localized)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 10)
    }

    private var metaText: String {
        String(
            format: "routines.card_meta".localized,
            routine.routineExercisesList.count,
            RoutineMetricsService.totalSets(for: routine),
            RoutineMetricsService.estimatedDurationMinutes(for: routine)
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("routine.empty.title".localized, systemImage: "dumbbell")
        } description: {
            Text("routine.empty.description".localized)
        } actions: {
            Button("routine.add_exercise".localized) {
                showingAddExercise = true
            }
            .buttonStyle(.onyxProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Exercise rows

    private var exerciseRows: some View {
        // Sort once and resolve every card's superset styling + the grouping in
        // a single pass each — `supersetStyling` filters + sorts the routine, so
        // calling it per card in the ForEach body would be O(n²) per render.
        let ordered = sortedExercises
        let styling = supersetStyling(for: ordered)
        let groups = supersetRowGroups(for: ordered)
        return ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            groupRow(group, styling: styling)

            // Link affordance between this row and the next one. Two members of
            // one superset never face each other here — they live inside the
            // same group.
            if supersetEditMode == nil,
               index < groups.count - 1,
               let current = group.members.last,
               let next = groups[index + 1].members.first,
               shouldShowLinkButton(between: current, and: next) {
                SupersetLinkButton {
                    linkExercises(current, next)
                }
            }
        }
    }

    /// A standalone exercise, or a whole superset wrapped in the group container
    /// that owns the connecting line.
    @ViewBuilder
    private func groupRow(_ group: RoutineExerciseGroup, styling: [UUID: SupersetCardStyling]) -> some View {
        if group.supersetId != nil, supersetEditMode == nil {
            SupersetGroupContainer(
                // Names feed the unlink controls' VoiceOver labels; same
                // fallback as RoutineExerciseCardDisplay so a missing exercise
                // never produces an empty announcement.
                members: group.members.map {
                    SupersetGroupContainer.Member(id: $0.id, name: $0.exercise?.name ?? "Unknown")
                },
                color: styling[group.id]?.color ?? DesignSystem.Colors.tint,
                onUnlink: { unlinkSuperset(after: $0) }
            ) {
                memberCards(group, styling: styling, showsSeams: true)
            }
        } else {
            memberCards(group, styling: styling, showsSeams: false)
        }
    }

    private func memberCards(
        _ group: RoutineExerciseGroup,
        styling: [UUID: SupersetCardStyling],
        showsSeams: Bool
    ) -> some View {
        ForEach(Array(group.members.enumerated()), id: \.element.id) { index, routineExercise in
            exerciseRow(
                routineExercise: routineExercise,
                display: RoutineExerciseCardDisplay(routineExercise),
                styling: styling[routineExercise.id] ?? .none
            )
            // Scroll anchor for the alternatives jump (scrollTo(exerciseId)).
            .id(routineExercise.id)

            // Room on the connector for the unlink control between this member
            // and the next one — the container draws the control itself.
            if showsSeams, index < group.members.count - 1 {
                SupersetSeamSpacer(memberAboveId: routineExercise.id)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(
        routineExercise: RoutineExercise,
        display: RoutineExerciseCardDisplay,
        styling: SupersetCardStyling
    ) -> some View {
        if supersetEditMode != nil {
            supersetSelectionCard(routineExercise, display: display)
                .padding(.vertical, 4)
        } else {
            normalExerciseCard(routineExercise, display: display, styling: styling)
                .padding(.vertical, 4)
        }
    }

    /// Superset edit mode: selection card.
    private func supersetSelectionCard(_ routineExercise: RoutineExercise, display: RoutineExerciseCardDisplay) -> some View {
        let isSelected = supersetEditSelection.contains(routineExercise.id)
        return supersetEditRow(for: routineExercise, display: display)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(supersetEditRowBackground(for: routineExercise))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.tint.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// One exercise as a self-contained card: header, parameter chips with their
    /// inline editors, and the expandable set + alternatives body.
    private func normalExerciseCard(
        _ routineExercise: RoutineExercise,
        display: RoutineExerciseCardDisplay,
        styling: SupersetCardStyling
    ) -> some View {
        let isExerciseExpanded = expandedExerciseId == routineExercise.id
        let openParameter = openParameters[routineExercise.id]
        // Superset members share one rest time, pre-resolved with the styling —
        // finding the owning member here would walk the whole routine per card.
        let displayedRestTime = styling.restTime ?? restTime(for: routineExercise)
        // The header already reserves the connector lane; everything below it
        // has to clear the same channel, otherwise the group's line runs
        // straight through the chip strip and the set list.
        let laneInset = styling.isMember ? ExerciseHeaderView.connectorLaneWidth : 0

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignSystem.Animation.spring) {
                    expandedAlternativeId = nil
                    expandedExerciseId = isExerciseExpanded ? nil : routineExercise.id
                }
            } label: {
                HStack(spacing: 10) {
                    ExerciseHeaderView(
                        routineExercise: routineExercise,
                        display: display,
                        supersetPosition: styling.position,
                        supersetTotal: styling.total,
                        supersetColor: styling.color,
                        isSupersetMember: styling.isMember,
                        onSupersetAction: routine.routineExercisesList.count >= 2 ? {
                            if let supersetId = routineExercise.supersetId {
                                enterSupersetEdit(for: supersetId)
                            } else {
                                enterSupersetCreate(initiatingExercise: routineExercise)
                            }
                        } : nil,
                        onEditAlternatives: { openAlternatives(for: routineExercise) }
                    )

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .rotationEffect(.degrees(isExerciseExpanded ? 180 : 0))
                        .animation(DesignSystem.Animation.spring, value: isExerciseExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: expandedExerciseId)

            // Chip strip — always visible, so pause and rep goal stay editable
            // without expanding the card.
            ExerciseParameterChips(
                restTime: displayedRestTime,
                targetRepMin: routineExercise.targetRepMin,
                targetRepMax: routineExercise.targetRepMax,
                openParameter: Binding(
                    get: { openParameters[routineExercise.id] },
                    set: { openParameters[routineExercise.id] = $0 }
                )
            )
            .padding(.top, 10)
            .padding(.leading, laneInset)

            if let openParameter {
                parameterEditor(openParameter, for: routineExercise, restTime: displayedRestTime)
                    .padding(.top, 8)
                    .padding(.leading, laneInset)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isExerciseExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .overlay(Color.white.opacity(0.05))
                        .padding(.top, 12)

                    expandedCardBody(for: routineExercise)
                }
                .padding(.leading, laneInset)
                // Reveal the body as the card grows in height (fluid in LazyVStack,
                // unlike List's row-height snap). Clipped by the card's .clipShape.
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(styling.color?.opacity(0.08) ?? Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(styling.color?.opacity(0.3) ?? Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            supersetContextMenu(for: routineExercise)
        }
    }

    @ViewBuilder
    private func parameterEditor(
        _ parameter: ExerciseCardParameter,
        for routineExercise: RoutineExercise,
        restTime displayedRestTime: TimeInterval
    ) -> some View {
        switch parameter {
        case .rest:
            RestTimeInlineEditor(restTime: displayedRestTime) { newValue in
                if routineExercise.isInSuperset {
                    updateSupersetRestTime(for: routineExercise, restTime: newValue)
                } else {
                    updateAllSetsRestTime(for: routineExercise, restTime: newValue)
                }
            }
        case .repRange:
            RepRangeInlineEditor(
                targetRepMin: routineExercise.targetRepMin,
                targetRepMax: routineExercise.targetRepMax
            ) { min, max in
                viewModel.updateRepRange(for: routineExercise, min: min, max: max)
            }
        }
    }

    @ViewBuilder
    private func expandedCardBody(for routineExercise: RoutineExercise) -> some View {
        if routineExercise.allSetsAtUpperLimit,
           !(overloadBannerDismissedForExercise[routineExercise.id] ?? false) {
            ProgressiveOverloadBanner(
                targetRepMax: routineExercise.targetRepMax ?? 0,
                isAssistance: routineExercise.exercise?.loadBehavior.isCounterweightAssistance == true,
                onIncrease: {
                    selectedExerciseForOverload = routineExercise
                },
                onDismiss: {
                    withAnimation(DesignSystem.Animation.spring) {
                        overloadBannerDismissedForExercise[routineExercise.id] = true
                    }
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        SetsSectionLabel(text: "routine.section.sets".localized)

        RoutineSetsEditor(
            sets: routineExercise.setsList,
            targetRepMin: routineExercise.targetRepMin,
            targetRepMax: routineExercise.targetRepMax,
            valueFocus: $isEditingSetValue,
            onAddSet: { _ = viewModel.addSet(to: routineExercise) },
            onRemoveSet: { viewModel.removeSet($0, from: routineExercise) },
            onSetChanged: { viewModel.updateSet($0) },
            onApplyToAll: { source, field in
                viewModel.applyToAllSets(from: source, field: field, in: routineExercise)
            }
        )

        RoutineAlternativesSection(
            routineExercise: routineExercise,
            viewModel: viewModel,
            expandedAlternativeId: $expandedAlternativeId,
            valueFocus: $isEditingSetValue,
            onAddAlternative: { addAlternativeTarget = routineExercise }
        )
    }

    // MARK: - Bottom inset (CTA / superset toolbar) & undo toast

    @ViewBuilder
    private var bottomInset: some View {
        if supersetEditMode != nil {
            HStack {
                Button("action.cancel".localized) {
                    cancelSupersetEdit()
                }
                .foregroundStyle(Color.white.opacity(0.6))

                Spacer()

                Text("superset.selected_count".localized(supersetEditSelection.count))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))

                Spacer()

                Button("action.done".localized) {
                    applySupersetEdit()
                }
                .fontWeight(.semibold)
                .foregroundStyle(canApplySupersetEdit ? DesignSystem.Colors.tint : Color.white.opacity(0.4))
                .disabled(!canApplySupersetEdit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DesignSystem.Colors.card)
            .overlay(alignment: .top) {
                Divider().overlay(Color.white.opacity(0.08))
            }
        } else if !routine.routineExercisesList.isEmpty && !isSorting {
            Button {
                HapticManager.shared.medium()
                workoutViewModel.startWorkout(routine: routine)
                showingActiveWorkout = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("routine.start_workout".localized)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(DesignSystem.Colors.tint)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: DesignSystem.Colors.tint.opacity(0.35), radius: 15, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.85), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    @ViewBuilder
    private var undoToastOverlay: some View {
        if removedExercise != nil {
            UndoToast(message: "routine.exercise_removed".localized, onUndo: undoRemoval)
                .padding(.horizontal, 16)
                .padding(.bottom, isSorting ? 24 : 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func toggleSortingMode() {
        HapticManager.shared.light()
        withAnimation(DesignSystem.Animation.spring) {
            if isSorting {
                isEditingSetValue = false
            } else {
                collapseCardState()
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "routine.sort_hint".localized
                )
            }
            isSorting.toggle()
        }
    }

}
