//
//  RoutineSetsEditor.swift
//  GymStreak
//
//  The always-editable set list of an exercise card (redesign v2): one row per
//  set (RoutineSetStepperRow) with a remove button, an index badge and
//  reps/weight steppers whose value can also be typed. Replaces the former
//  tap-to-expand RoutineSetRowView and AlternativeSetsInlineEditor — the primary
//  exercise and its alternatives now share one editor.
//

import SwiftUI

/// Abstraction over `ExerciseSet` (also used unpersisted in the picker flow) and
/// `AlternativeExerciseSet` so one editor serves both.
// NOTE: deliberately does NOT inherit Identifiable — @Model types already get
// Identifiable via PersistentModel, and re-stating it in a retroactive
// conformance emits a duplicate conformance descriptor (linker error).
protocol AlternativeEditableSet: AnyObject {
    var id: UUID { get }
    var reps: Int { get set }
    var weight: Double { get set }
    var restTime: TimeInterval { get set }
    var order: Int { get set }
}

extension ExerciseSet: AlternativeEditableSet {}
extension AlternativeExerciseSet: AlternativeEditableSet {}

// MARK: - Set list

/// The "SÄTZE" block of an exercise card: rows, the apply-to-all banner for the
/// most recently edited row, and the inline add-set button.
struct RoutineSetsEditor<SetType: AlternativeEditableSet>: View {
    let sets: [SetType]
    /// Section heading rendered on the same line as the column legend. Pass nil
    /// where the host already draws its own heading above the editor.
    var sectionTitle: String? = nil
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var valueFocus: FocusState<Bool>.Binding
    /// Appends a new set (seeded from the last one).
    let onAddSet: () -> Void
    let onRemoveSet: (SetType) -> Void
    /// Persistence hook, called after a set's values changed.
    let onSetChanged: (SetType) -> Void
    /// Copies the given set's reps + weight onto every set of this exercise.
    let onApplyToAll: (SetType, ApplyToAllType) -> Void

    /// Which row was edited last — the apply-to-all banner is offered under it
    /// until the user applies or dismisses it.
    @State private var recentlyEditedSetId: UUID?
    @State private var recentlyEditedField: ApplyToAllType?

    var body: some View {
        // Sort once per body pass — `sets` is a model collection.
        let sortedSets = sets.sorted { $0.order < $1.order }
        return VStack(spacing: 6) {
            RoutineSetsHeaderRow(title: sectionTitle)

            ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                VStack(spacing: 6) {
                    RoutineSetStepperRow(
                        index: index,
                        reps: set.reps,
                        weight: set.weight,
                        targetRepMin: targetRepMin,
                        targetRepMax: targetRepMax,
                        canRemove: sortedSets.count > 1,
                        valueFocus: valueFocus,
                        onRepsChange: { newValue in
                            guard newValue != set.reps else { return }
                            set.reps = newValue
                            onSetChanged(set)
                            noteEdit(of: set, field: .reps)
                        },
                        onWeightChange: { newValue in
                            guard newValue != set.weight else { return }
                            set.weight = newValue
                            onSetChanged(set)
                            noteEdit(of: set, field: .weight)
                        },
                        onRemove: {
                            if recentlyEditedSetId == set.id { clearBanner() }
                            withAnimation(DesignSystem.Animation.spring) {
                                onRemoveSet(set)
                            }
                        }
                    )

                    if sortedSets.count > 1,
                       recentlyEditedSetId == set.id,
                       let field = recentlyEditedField {
                        ApplyToAllBanner(
                            type: field,
                            setCount: sortedSets.count,
                            onApply: {
                                withAnimation(DesignSystem.Animation.spring) {
                                    onApplyToAll(set, field)
                                    clearBanner()
                                }
                            },
                            onDismiss: {
                                withAnimation(DesignSystem.Animation.spring) { clearBanner() }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            DashedCreateButton(title: "exercise.add_set".localized, tinted: true) {
                clearBanner()
                withAnimation(DesignSystem.Animation.spring) {
                    onAddSet()
                }
            }
        }
    }

    private func noteEdit(of set: SetType, field: ApplyToAllType) {
        guard sets.count > 1 else { return }
        withAnimation(DesignSystem.Animation.spring) {
            recentlyEditedSetId = set.id
            recentlyEditedField = field
        }
    }

    private func clearBanner() {
        recentlyEditedSetId = nil
        recentlyEditedField = nil
    }
}

// MARK: - Column legend

/// The set list's header line: the section title on the left, and the reps /
/// weight units once each, centred over the columns they label.
///
/// Those units used to sit beside every value in every row, which is what made
/// `RoutineSetStepperRow` wider than a superset member card — see the budget
/// note on `RoutineSetStepperRow.Metrics`. Here they cost one label per list
/// instead of one per row, and they share the title's line, so at the call sites
/// that pass a title they cost no height at all.
///
/// The weight unit is **derived**, never literal: it is the user's only in-place
/// confirmation of which unit the field is in, so it has to flip to "LB" with
/// the setting exactly as the row's old inline label did.
///
/// Alignment is built from `RoutineSetStepperRow.Metrics` placeholders rather
/// than a tuned leading padding, so it cannot drift when one of those widths
/// changes.
struct RoutineSetsHeaderRow: View {
    var title: String?

    @Environment(\.weightUnit) private var weightUnit

    private typealias Metrics = RoutineSetStepperRow.Metrics

    var body: some View {
        // A ZStack, not `.overlay(alignment: .leading)`: the title is the taller
        // of the two (10.5 pt plus SetsSectionLabel's own top padding, against
        // the 9.5 pt column labels), so the container has to size to the union
        // of both. An overlay would size to the legend alone and let the title
        // bleed into the first set row.
        ZStack(alignment: .leading) {
            HStack(spacing: Metrics.outerSpacing) {
                Color.clear.frame(width: Metrics.removeButtonWidth, height: 0)
                Color.clear.frame(width: Metrics.indexWidth, height: 0)

                HStack(spacing: Metrics.groupSpacing) {
                    columnLabel("set.reps_unit".localized)
                        .frame(width: Metrics.repsGroupWidth)

                    Spacer(minLength: 2)

                    columnLabel(WeightFormatting.unitWord(weightUnit))
                        .frame(width: Metrics.weightGroupWidth)
                }
            }
            .padding(.horizontal, Metrics.rowPadding)

            if let title {
                SetsSectionLabel(text: title)
            }
        }
    }

    /// One step quieter than the section label beside it — the line has to read
    /// title, then column, then value, with the value the brightest of the
    /// three. Hidden from VoiceOver because each row already speaks its own
    /// full label ("Set 1, 10 reps, 20 kilograms"); unhidden these would add two
    /// junk stops per exercise, once more per alternative.
    private func columnLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Color.white.opacity(0.32))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityHidden(true)
    }
}
