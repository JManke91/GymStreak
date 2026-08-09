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
    /// Called with the finalized sets (rest time and order applied), the picked
    /// alternatives and the rep-range goal; the caller owns persistence.
    var onSave: (Exercise, [ExerciseSet], [PendingAlternative], Int?, Int?) -> Void

    /// Set schemes offered on the empty state — the fastest way out of "no sets".
    private static let quickSchemes: [(sets: Int, reps: Int)] = [(3, 8), (3, 10), (4, 12)]

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                exerciseHeader
                summaryStrip
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

    /// Sets · volume · rest at a glance, so the configuration reads back without
    /// re-scanning the rows. The reduce runs over the local set array only — a
    /// handful of value reads, no relationship traversal.
    private var summaryStrip: some View {
        let volume = sets.reduce(0.0) { $0 + Double($1.reps) * $1.weight }
        return HStack(spacing: 0) {
            summaryColumn(
                value: "\(sets.count)",
                label: "routine.section.sets".localized
            )
            summaryDivider
            summaryColumn(
                value: volume > 0 ? WeightFormatting.label(volume) : "—",
                label: "configure_exercise.summary.volume".localized
            )
            summaryDivider
            summaryColumn(
                value: globalRestTime > 0 ? TimeFormatting.formatRestTime(globalRestTime) : "rest_timer.off".localized,
                label: "rest_timer.rest_short".localized
            )
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
        .background(DesignSystem.Colors.tint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func summaryColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.7)
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(DesignSystem.Colors.tint.opacity(0.16))
            .frame(width: 1, height: 30)
    }

    // MARK: - Sets

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: "routine.section.sets".localized,
                hint: sets.isEmpty ? nil : "configure_exercise.sets_planned".localized(sets.count)
            )

            sectionCard {
                if sets.isEmpty {
                    emptySetsState
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
        }
    }

    private var emptySetsState: some View {
        VStack(spacing: 14) {
            Text("configure_exercise.empty.hint".localized)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                ForEach(Array(Self.quickSchemes.enumerated()), id: \.offset) { _, scheme in
                    Button {
                        HapticManager.shared.light()
                        withAnimation(DesignSystem.Animation.spring) {
                            applyQuickScheme(scheme)
                        }
                    } label: {
                        Text("configure_exercise.quick_scheme".localized(scheme.sets, scheme.reps))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(DesignSystem.Colors.tint.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DesignSystem.Colors.tint.opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            DashedCreateButton(title: "configure_exercise.single_set".localized, compact: true) {
                withAnimation(DesignSystem.Animation.spring) { addSet() }
            }
        }
    }

    // MARK: - Rep goal

    private var repGoalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
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
            sectionHeader(
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
            sectionHeader(
                title: "configure_exercise.alternatives.header".localized,
                hint: pendingAlternatives.isEmpty
                    ? "configure_exercise.optional".localized
                    : "\(pendingAlternatives.count)"
            )

            sectionCard {
                PendingAlternativesSection(
                    alternatives: $pendingAlternatives,
                    showingPicker: $showingAlternativePicker,
                    expandedAlternativeId: $expandedAlternativeId,
                    valueFocus: $isEditingSetValue
                )
            }
        }
    }

    // MARK: - Sticky CTA

    private var addCTA: some View {
        Button {
            HapticManager.shared.light()
            finishConfiguration()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
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

    // MARK: - Shared section chrome

    private func sectionHeader(title: String, hint: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Color.white.opacity(0.42))

            if let hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Set mutations

    private func applyQuickScheme(_ scheme: (sets: Int, reps: Int)) {
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

    private func finishConfiguration() {
        let ordered = sets.sorted { $0.order < $1.order }
        for (index, set) in ordered.enumerated() {
            set.restTime = globalRestTime
            set.order = index
        }

        onSave(exercise, ordered, pendingAlternatives, targetRepMin, targetRepMax)
    }
}
