//
//  WorkoutDetailView.swift
//  GymStreak
//
//  Redesigned per History Redesign (2026-04-22):
//  - Editorial header with type chip + date
//  - 4-metric stat grid (Duration / Sets / Volume / Intensity)
//  - Apple Health banner when session was written to HealthKit
//  - Per-exercise block with vs-previous-session comparison strip, per-set
//    delta chips, and "First session" badge for new exercises
//

import SwiftUI
import SwiftData
import HealthKit

struct WorkoutDetailView: View {
    let workout: WorkoutSession
    @ObservedObject var viewModel: WorkoutViewModel
    @EnvironmentObject private var dependencies: AppDependencies
    /// Kept only to pass through to the (out-of-scope) AI Coach analysis ViewModel API.
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weightUnit) private var weightUnit

    @State private var prDetails: [UUID: PersonalRecordService.PRDetail] = [:]
    @State private var healthKitKcal: Double?
    @State private var comparisons: [UUID: ExerciseComparisonResult] = [:]
    @State private var analysisVM = WorkoutAnalysisViewModel()
    @State private var hasPreviousSession: Bool = false
    /// Trained-muscle picture for the map card. Derived once per load — the aggregation walks
    /// the session's exercises and sets, so it must stay off the render path.
    @State private var muscleMap: MuscleMapCardModel = .empty
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    /// Set the moment deletion is confirmed, so `body` stops walking
    /// `workout.workoutExercisesList` while the pop animation runs and the delete awaits
    /// the History gate. `dismiss()` does not unmount this view synchronously, and every
    /// `@Published` change on `viewModel` — including the `historyVersion` bump the delete
    /// itself causes — re-evaluates this body. Reading a cascade-deleted `WorkoutExercise`
    /// there is an uncatchable SwiftData trap; see `HistoryStoreGate`.
    @State private var isBeingDeleted = false
    /// Which exercise's weight-increase sheet is open (after-the-fact overload).
    @State private var overloadSheetExercise: WorkoutExercise?
    /// New live-template weight per exercise applied from this history view. The
    /// historical session is never mutated, so applied state is tracked here.
    @State private var appliedTemplateWeights: [UUID: Double] = [:]
    /// Exercises whose increase was already applied from the Watch's
    /// post-workout recap (progressive-overload ticket 05). Separate from
    /// `appliedTemplateWeights` because a pyramid/drop scheme is applied with no
    /// single weight to show — "applied" and "applied to X kg" are not the same
    /// fact, and collapsing them would make the card state a weight that is
    /// wrong for every set but the first.
    @State private var appliedOverloadExerciseIDs: Set<UUID> = []

    private var workoutType: WorkoutType {
        WorkoutType.classify(routineName: workout.routineName)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                // The card owns no outer margin of its own — the sections around it here are
                // laid out edge to edge, so this screen supplies the 16 pt the design asks for.
                MuscleMapCardView(model: muscleMap, horizontalMargin: 16)
                statsGrid
                progressiveOverloadSection
                if workout.healthKitWorkoutId != nil {
                    healthKitBanner
                }
                if !workout.notes.isEmpty {
                    notesSection
                }
                coachSection
                exercisesSection
                Color.clear.frame(height: 40)
            }
        }
        // The muscle map card is inserted above the fold once its aggregation lands, and
        // without this the scroll view compensates by keeping the content below anchored —
        // the screen would open already scrolled past the workout title.
        .defaultScrollAnchor(.top)
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            if !isBeingDeleted {
                content
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        HapticManager.shared.light()
                        showingEdit = true
                    } label: {
                        Label("edit_workout.title".localized, systemImage: "square.and.pencil")
                    }
                    Button(role: .destructive) {
                        HapticManager.shared.light()
                        showingDeleteConfirmation = true
                    } label: {
                        Label("action.delete".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("history.detail.more".localized)
            }
        }
        .task {
            loadMuscleMap()
            await loadAppliedOverloads()
            await loadPRs()
            await loadHealthKitKcal()
            await loadComparisons()
            loadCoachState()
        }
        .sheet(isPresented: $showingEdit, onDismiss: reloadAfterEdit) {
            EditWorkoutSessionView(workout: workout, viewModel: viewModel)
        }
        .deleteWorkoutConfirmation(
            isPresented: $showingDeleteConfirmation,
            // Short-circuited: this modifier sits outside the `isBeingDeleted` guard, so
            // without it the alert would still read the tombstoned session.
            hasHealthKitWorkout: !isBeingDeleted && workout.healthKitWorkoutId != nil,
            onDelete: deleteWorkout
        )
    }

    /// Blanks the content and pops the screen before the session is removed, so no view
    /// body ever re-reads a deleted `@Model`. `dismiss()` alone is not enough: it does not
    /// unmount synchronously, and the delete now awaits the History gate — `isBeingDeleted`
    /// is what actually stops `body` from walking the session graph in between. Deletion
    /// bumps the History invalidation version, which causes the actor-owned snapshot to
    /// reload.
    private func deleteWorkout(alsoFromHealthKit: Bool) {
        isBeingDeleted = true
        // Its stream task captures this `WorkoutSession` and reads its exercise/set graph
        // across several suspensions, so it would outlive the delete otherwise.
        analysisVM.cancel()
        dismiss()
        HapticManager.shared.success()
        Task {
            await viewModel.deleteWorkout(workout, alsoFromHealthKit: alsoFromHealthKit)
        }
    }

    /// Re-derives PR badges, vs-previous comparisons and coach state after the user
    /// edits the session. The set grid itself is @Model-observed and updates on its own.
    private func reloadAfterEdit() {
        Task {
            loadMuscleMap()
            await loadPRs()
            await loadComparisons()
            loadCoachState()
        }
    }

    // MARK: - Header

    private var header: some View {
        WorkoutSessionHeaderView(
            type: workoutType,
            dateText: dateString,
            title: workout.routineName
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// Hoisted out of `body`: `header` reads `dateString` on every state change, and building a
    /// `DateFormatter` there is the allocation `docs/history-performance.md` was written about.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE d. MMM")
        return formatter
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: workout.startTime)
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        WorkoutStatGrid(
            durationText: "\(Int(workout.duration / 60))m",
            setsText: "\(workout.completedSetsCount)",
            volumeText: WeightFormatting.volume(workout.totalVolume, in: weightUnit),
            intensityText: "\(workout.completionPercentage)"
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Progressive overload (after-the-fact)

    /// Exercises whose completed sets hit the top of their rep range. Re-surfaces
    /// the rep-goal achievement the history redesign dropped, and lets the user
    /// apply the increase to the live routine template after the workout is done.
    private var qualifyingOverloadExercises: [WorkoutExercise] {
        workout.workoutExercisesList
            .filter { $0.hasRepRangeGoal && $0.allCompletedSetsAtUpperLimit }
            .sorted { $0.order < $1.order }
    }

    @ViewBuilder
    private var progressiveOverloadSection: some View {
        let exercises = qualifyingOverloadExercises
        if !exercises.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("rep_range.ready_for_more".localized.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                VStack(spacing: 8) {
                    ForEach(exercises, id: \.id) { exercise in
                        overloadCard(for: exercise)
                    }
                }
                .padding(.horizontal, 16)
            }
            .sheet(item: $overloadSheetExercise) { exercise in
                WeightIncreaseSheet(
                    workoutExercise: exercise,
                    // The apply raises the LIVE template, so preview that —
                    // not what this historical workout happened to perform.
                    templateFirstSet: viewModel.overloadTemplateFirstSet(
                        from: workout, for: exercise
                    ),
                    onApply: { increment in
                        if let newWeight = viewModel.applyProgressiveOverloadFromHistory(
                            from: workout, for: exercise, weightIncrement: increment
                        ) {
                            withAnimation(DesignSystem.Animation.spring) {
                                appliedTemplateWeights[exercise.id] = newWeight
                            }
                            HapticManager.shared.success()
                        }
                        overloadSheetExercise = nil
                    },
                    onCancel: { overloadSheetExercise = nil }
                )
            }
        }
    }

    private func overloadCard(for exercise: WorkoutExercise) -> some View {
        let appliedNow = appliedTemplateWeights[exercise.id]
        // Applied here, or already applied from the Watch recap — the latter can
        // be true with no weight to show (pyramid/drop scheme).
        let isApplied = appliedNow != nil || appliedOverloadExerciseIDs.contains(exercise.id)
        // Only the never-progressed exercises whose live template is gone show the
        // no-op note; a mid-workout-applied one keeps its confirmed state.
        let unavailable = !isApplied
            && !exercise.progressiveOverloadApplied
            && !viewModel.hasResolvableOverloadTemplate(from: workout, for: exercise)

        let templateFirstSet = viewModel.overloadTemplateFirstSet(from: workout, for: exercise)
        return ProgressiveOverloadCard(
            exercise: exercise,
            libraryExercise: viewModel.performedExercise(in: workout, for: exercise),
            canUndo: false,
            appliedOverride: isApplied,
            appliedWeight: appliedNow,
            // An increase applied on iPhone during the workout leaves no
            // correlation record and no bumped set to read a weight off, so its
            // confirmed row states that all sets moved rather than a number.
            hasAmbiguousAppliedWeight: appliedNow == nil,
            templateWeight: templateFirstSet?.weight,
            isTemplateUnavailable: unavailable,
            onIncrease: { overloadSheetExercise = exercise },
            onUndo: {}
        )
    }

    // MARK: - HealthKit banner

    private var healthKitBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 1, green: 0.42, blue: 0.42))
                    .frame(width: 24, height: 24)
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("history.detail.healthkit.title".localized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(healthKitSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 1, green: 0.42, blue: 0.42).opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var healthKitSubtitle: String {
        let minutes = Int(workout.duration / 60)
        let durationString = "\(minutes) Min"
        if let kcal = healthKitKcal {
            return String(format: "history.detail.healthkit.subtitle_with_kcal".localized,
                          durationString, "\(Int(kcal))")
        } else {
            return String(format: "history.detail.healthkit.subtitle".localized, durationString)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("history.detail.notes".localized.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(workout.notes)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Coach

    @ViewBuilder
    private var coachSection: some View {
        if isCoachVisible {
            Group {
                switch analysisVM.state {
                case .idle:
                    CoachWorkoutAnalysisButton(routineName: workout.routineName) {
                        analysisVM.generate(
                            workout: workout,
                            locale: Locale.current,
                            weightUnit: weightUnit,
                            modelContext: modelContext,
                            exerciseProgress: dependencies.exerciseProgressService
                        )
                    }
                    .transition(.opacity)

                case .preparing, .streaming, .success, .unavailable, .insufficientData, .error:
                    CoachWorkoutAnalysisSurface(
                        state: analysisVM.state,
                        routineName: workout.routineName,
                        onRegenerate: {
                            analysisVM.regenerate(
                                workout: workout,
                                locale: Locale.current,
                                weightUnit: weightUnit,
                                modelContext: modelContext,
                                exerciseProgress: dependencies.exerciseProgressService
                            )
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: analysisVM.state)
            .padding(.horizontal, 16)
        }
    }

    /// Whether the AI Coach button/surface should be visible.
    private var isCoachVisible: Bool {
        AICoachPreferences.shared.isWorkoutDetailEffectivelyEnabled
        && AICoachAvailability.shared.isAvailable
        && hasPreviousSession
    }

    @MainActor
    private func loadCoachState() {
        // Runs last in the `.task` chain, after three awaits, and `prepareCoachState` reads the
        // session — so it needs the same tombstone check as the two loaders above.
        guard !isBeingDeleted else { return }
        // Aggregation, cache lookup and model prewarming all live on the ViewModel —
        // the view only reads back whether a previous session exists.
        hasPreviousSession = analysisVM.prepareCoachState(session: workout, modelContext: modelContext)
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("history.detail.exercises".localized)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 4)

            let exercises = workout.workoutExercisesList.sorted(by: { $0.order < $1.order })
            VStack(spacing: 8) {
                ForEach(exercises, id: \.id) { exercise in
                    WorkoutDetailExerciseBlock(
                        display: WorkoutDetailExerciseDisplay(exercise),
                        prDetail: prDetails[exercise.id],
                        comparison: comparisons[exercise.id]
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Data loading

    /// Derives which muscle regions this session trained. One traversal of the session graph,
    /// run when the screen loads and after an edit — never from a view body.
    @MainActor
    private func loadMuscleMap() {
        muscleMap = MuscleMapCardModel.make(
            from: MuscleLoadAggregator.aggregate(session: workout),
            reading: .performed
        )
    }

    /// Seeds the confirmed state for increases the user already applied from
    /// the Watch's post-workout recap (progressive-overload ticket 05).
    ///
    /// Those arrive as a template-only transaction that deliberately never
    /// amends the recorded workout, so the session itself carries no trace of
    /// them — without this the card would invite the same increase again, and a
    /// second tap would raise the template twice. A workout with no correlation
    /// (any older one included) stays ordinarily eligible.
    @MainActor
    private func loadAppliedOverloads() async {
        let applied = await dependencies.appliedOverloadCorrelation.appliedOverloads(
            forWorkout: workout.id
        )
        // The gate only excludes the model actor's walks; a main-actor continuation like
        // this one resumes *after* the delete has committed. `isBeingDeleted` is set on
        // this actor before the delete task is created, so seeing it false here means the
        // session is still alive. Without the guard the loop below faults deleted rows.
        guard !isBeingDeleted else { return }
        guard !applied.isEmpty else { return }
        // Correlated by routine slot — the only id both the Watch's template
        // target and this recorded exercise agree on.
        for exercise in workout.workoutExercisesList {
            guard let slotID = exercise.routineExerciseId, let record = applied[slotID] else { continue }
            appliedOverloadExerciseIDs.insert(exercise.id)
            // Nil for a pyramid/drop scheme: applied, but with no single weight
            // that would be true of every set.
            if let weight = record.newWeight { appliedTemplateWeights[exercise.id] = weight }
        }
    }

    @MainActor
    private func loadPRs() async {
        do {
            prDetails = try await dependencies.historySnapshotProvider.fetchPRDetails(
                sessionID: workout.id
            )
        } catch is CancellationError {
            return
        } catch {
            prDetails = [:]
        }
    }

    @MainActor
    private func loadComparisons() async {
        // Each result carries the exercise it describes, so this no longer pairs the two
        // arrays positionally — a `zip` that silently truncates or mispairs the moment
        // the orderings diverge.
        let results = await dependencies.exerciseProgressService.compareWithPrevious(workout: workout)
        // `compareWithPrevious` no longer reads the session after its own suspension — it
        // snapshots it first — but publishing rows for a workout that is being deleted still
        // re-renders a screen that is on its way out, so the flag check stays.
        guard !isBeingDeleted else { return }
        comparisons = Dictionary(
            results.map { ($0.workoutExerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @MainActor
    private func loadHealthKitKcal() async {
        guard let externalId = workout.healthKitWorkoutId else { return }
        let store = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalId.uuidString
        )
        let result: Double? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workout = samples?.first as? HKWorkout
                let kcal = workout?.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
        healthKitKcal = result
    }
}
