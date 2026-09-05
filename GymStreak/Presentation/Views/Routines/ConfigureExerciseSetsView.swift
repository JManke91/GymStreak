//
//  ConfigureExerciseSetsView.swift
//  GymStreak
//
//  "Übung hinzufügen" — the screen reached after picking an exercise for a
//  routine (redesign 2026-08). Replaces the former List form that lived inside
//  RoutineExercisePickerView.swift: an exercise identity header, a live summary
//  (sets · volume · rest), the shared set editor, rep-goal and rest-timer panels,
//  alternatives and a sticky add CTA.
//
//  It is also the *edit* screen for an exercise already added to a routine
//  draft (CreateRoutineView): pass `existingConfiguration` and it opens on that
//  configuration instead of an empty one. That case retired the legacy Form
//  `ConfigureExerciseView`, so adding and editing look identical.
//
//  The set editor, rep-range editor and rest-time editor are the same components
//  the routine detail screen uses, so both screens edit an exercise identically.
//

import SwiftUI

struct ConfigureExerciseSetsView: View {
    let exercise: Exercise
    var navigationTitleKey = "add_to_routine.add_title"
    /// CTA label used when no `destinationName` is given (add-to-workout flow).
    var saveButtonKey = "action.save"
    /// Routine the exercise is being added to — makes the CTA name it.
    var destinationName: String? = nil
    var includesAlternatives = true
    /// Configuration to reopen on instead of starting from an empty scheme.
    /// Non-nil puts the screen in edit mode: the CTA saves changes and pops, and
    /// backing out saves too (the legacy edit form's behaviour, kept so edits
    /// can't be lost on a swipe-back).
    var existingConfiguration: ExistingConfiguration? = nil
    /// Called with the finalized sets (rest time and order applied), the picked
    /// alternatives and the rep-range goal; the caller owns persistence.
    var onSave: (Exercise, [ExerciseSet], [PendingAlternative], Int?, Int?) -> Void

    /// Snapshot of an already-configured — but not yet persisted — exercise.
    struct ExistingConfiguration {
        var sets: [ExerciseSet]
        var alternatives: [PendingAlternative]
        var targetRepMin: Int?
        var targetRepMax: Int?
    }

    /// Set schemes offered on the empty state — the fastest way out of "no sets".
    private static let quickSchemes = [
        QuickSetScheme(sets: 3, reps: 8),
        QuickSetScheme(sets: 3, reps: 10),
        QuickSetScheme(sets: 4, reps: 12)
    ]

    @Environment(\.dismiss) private var dismiss

    @State private var sets: [ExerciseSet] = []
    @State private var globalRestTime: TimeInterval = 0
    @State private var targetRepMin: Int?
    @State private var targetRepMax: Int?
    /// Alternative exercises picked before save; materialized by the caller.
    @State private var pendingAlternatives: [PendingAlternative] = []
    @State private var showingAlternativePicker = false
    @State private var expandedAlternativeId: UUID?
    /// Shared across every set row so one Done bar dismisses whichever value is
    /// being typed.
    @FocusState private var isEditingSetValue: Bool
    /// `onAppear` fires again when popping back from the alternative picker, so
    /// the seed has to run exactly once — otherwise returning from the picker
    /// would discard in-progress edits.
    @State private var hasSeededInitialState = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                exerciseHeader
                ConfigureSummaryStrip(sets: sets, restTime: globalRestTime)
                setsSection
                repGoalSection
                restTimerSection
                if includesAlternatives {
                    alternativesSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(DesignSystem.Colors.background)
        // No .scrollDismissesKeyboard here — it breaks the pinned Done bar
        // (see keyboardDoneBar, FB13296535).
        .keyboardDoneBar(isFocused: $isEditingSetValue)
        .safeAreaInset(edge: .bottom) { addCTA }
        .navigationDestination(isPresented: $showingAlternativePicker) {
            AlternativeExercisePicker(
                primaryExercise: exercise,
                excludedExerciseIds: Set(pendingAlternatives.map(\.exercise.id)).union([exercise.id]),
                onSelect: { picked in
                    let alternative = PendingAlternative(exercise: picked, seededFrom: sets, restTime: globalRestTime)
                    pendingAlternatives.append(alternative)
                    // Open the new alternative's editor so its weights can be
                    // defined right away.
                    expandedAlternativeId = alternative.id
                    showingAlternativePicker = false
                }
            )
        }
        .navigationTitle(navigationTitleKey.localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: seedInitialStateIfNeeded)
        .onDisappear {
            // Edit mode has no explicit cancel, so leaving the screen commits
            // what is on it. Never commit an empty scheme — an exercise with no
            // sets is not a valid routine entry.
            if isEditing && !sets.isEmpty {
                commitConfiguration()
            }
        }
    }

    private var isEditing: Bool { existingConfiguration != nil }

    /// Copies the incoming configuration: the caller still holds the originals,
    /// and this screen must not mutate its draft while the user is editing.
    private func seedInitialStateIfNeeded() {
        guard !hasSeededInitialState else { return }
        hasSeededInitialState = true
        guard let existingConfiguration else { return }

        sets = existingConfiguration.sets.map(Self.copy)
        globalRestTime = existingConfiguration.sets.first?.restTime ?? 0
        targetRepMin = existingConfiguration.targetRepMin
        targetRepMax = existingConfiguration.targetRepMax
        pendingAlternatives = existingConfiguration.alternatives.map {
            PendingAlternative(exercise: $0.exercise, sets: $0.sets.map(Self.copy))
        }
    }

    private static func copy(_ set: ExerciseSet) -> ExerciseSet {
        ExerciseSet(reps: set.reps, weight: set.weight, restTime: set.restTime, order: set.order)
    }

    // MARK: - Header

    private var exerciseHeader: some View {
        HStack(spacing: 14) {
            ExerciseAvatarView(
                muscleGroups: exercise.muscleGroups,
                equipmentType: exercise.equipmentType,
                size: 56,
                radius: 18
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(exercise.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .kerning(-0.6)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8) {
                    MuscleChipView(muscleGroup: exercise.primaryMuscleGroup, small: true)
                    EquipmentTagView(equipmentType: exercise.equipmentType)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Sets

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConfigureSectionHeader(
                title: "routine.section.sets".localized,
                hint: sets.isEmpty ? nil : "configure_exercise.sets_planned".localized(sets.count)
            )

            Group {
                if sets.isEmpty {
                    ConfigureEmptySetsState(
                        schemes: Self.quickSchemes,
                        onApplyScheme: applyQuickScheme,
                        onAddSingleSet: addSet
                    )
                } else {
                    RoutineSetsEditor(
                        sets: sets,
                        targetRepMin: targetRepMin,
                        targetRepMax: targetRepMax,
                        valueFocus: $isEditingSetValue,
                        onAddSet: addSet,
                        onRemoveSet: removeSet,
                        onSetChanged: { _ in },
                        onApplyToAll: { source, field in
                            for set in sets {
                                switch field {
                                case .reps: set.reps = source.reps
                                case .weight: set.weight = source.weight
                                }
                            }
                        }
                    )
                }
            }
            .configureSectionCard()
        }
    }

    // MARK: - Rep goal

    private var repGoalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConfigureSectionHeader(
                title: "configure_exercise.rep_goal".localized,
                hint: repGoalHint
            )

            RepRangeInlineEditor(
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax,
                isProminent: false
            ) { min, max in
                targetRepMin = min
                targetRepMax = max
            }
        }
    }

    private var repGoalHint: String {
        guard let min = targetRepMin, let max = targetRepMax else {
            return "configure_exercise.optional".localized
        }
        return "rep_range.value".localized(min, max)
    }

    // MARK: - Rest timer

    private var restTimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConfigureSectionHeader(
                title: "rest_timer.config.title".localized,
                hint: globalRestTime > 0
                    ? TimeFormatting.formatRestTime(globalRestTime)
                    : "rest_timer.off".localized
            )

            RestTimeInlineEditor(restTime: globalRestTime, isProminent: false) { newValue in
                globalRestTime = newValue
                for set in sets { set.restTime = newValue }
            }
        }
    }

    // MARK: - Alternatives

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConfigureSectionHeader(
                title: "configure_exercise.alternatives.header".localized,
                hint: pendingAlternatives.isEmpty
                    ? "configure_exercise.optional".localized
                    : "\(pendingAlternatives.count)"
            )

            PendingAlternativesSection(
                alternatives: $pendingAlternatives,
                showingPicker: $showingAlternativePicker,
                expandedAlternativeId: $expandedAlternativeId,
                valueFocus: $isEditingSetValue
            )
            .configureSectionCard()
        }
    }

    // MARK: - Sticky CTA / commit

    private var addCTA: some View {
        Button {
            HapticManager.shared.light()
            commitConfiguration()
            // Edit mode is a push with no owning sheet to close, so the screen
            // pops itself; the add flows are dismissed by their caller.
            if isEditing { dismiss() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isEditing ? "checkmark" : "plus")
                    .font(.system(size: 15, weight: .bold))
                Text(ctaTitle)
                    .font(.system(size: 15.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(sets.isEmpty ? Color.white.opacity(0.35) : DesignSystem.Colors.textOnTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(sets.isEmpty ? Color.white.opacity(0.08) : DesignSystem.Colors.tint)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sets.isEmpty)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [DesignSystem.Colors.background.opacity(0), DesignSystem.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -28)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }

    private var ctaTitle: String {
        if let destinationName, !destinationName.isEmpty {
            return "configure_exercise.add_to_named".localized(destinationName)
        }
        return saveButtonKey.localized
    }

    // MARK: - Set mutations

    private func applyQuickScheme(_ scheme: QuickSetScheme) {
        sets = (0..<scheme.sets).map { order in
            ExerciseSet(reps: scheme.reps, weight: 0.0, restTime: globalRestTime, order: order)
        }
    }

    private func addSet() {
        let last = sets.max(by: { $0.order < $1.order })
        sets.append(
            ExerciseSet(
                reps: last?.reps ?? 10,
                weight: last?.weight ?? 0.0,
                restTime: globalRestTime,
                order: (last?.order ?? -1) + 1
            )
        )
    }

    private func removeSet(_ set: ExerciseSet) {
        sets.removeAll { $0.id == set.id }
        for (order, remaining) in sets.sorted(by: { $0.order < $1.order }).enumerated() {
            remaining.order = order
        }
    }

    /// Finalizes rest time and ordering, then hands the configuration to the
    /// caller. Idempotent — in edit mode it can run more than once (the CTA, and
    /// every time the screen goes away, which includes pushing the alternative
    /// picker).
    ///
    /// It hands over **copies**, never the live `@State` objects: `ExerciseSet`
    /// and `PendingAlternative` are reference types, so committing the originals
    /// would leave the caller's draft aliasing this screen's state and every
    /// later keystroke would write straight through it.
    private func commitConfiguration() {
        let ordered = sets.sorted { $0.order < $1.order }
        for (index, set) in ordered.enumerated() {
            set.restTime = globalRestTime
            set.order = index
        }

        onSave(
            exercise,
            ordered.map(Self.copy),
            pendingAlternatives.map { PendingAlternative(exercise: $0.exercise, sets: $0.sets.map(Self.copy)) },
            targetRepMin,
            targetRepMax
        )
    }
}
