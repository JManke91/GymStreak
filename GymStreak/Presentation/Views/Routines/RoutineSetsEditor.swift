//
//  RoutineSetsEditor.swift
//  GymStreak
//
//  The always-editable set list of an exercise card (redesign v2): one row per
//  set with a remove button, an index badge and reps/weight steppers whose value
//  can also be typed. Replaces the former tap-to-expand RoutineSetRowView and
//  AlternativeSetsInlineEditor — the primary exercise and its alternatives now
//  share one editor.
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

// MARK: - Single set row

/// Value-typed set row: takes plain numbers, reports edits through callbacks.
/// Keeping models out of the row avoids a relationship read per row.
struct RoutineSetStepperRow: View {
    let index: Int
    let reps: Int
    let weight: Double
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var canRemove: Bool = true
    /// Shared "a set value is being typed" flag driving the screen's Done bar.
    var valueFocus: FocusState<Bool>.Binding
    let onRepsChange: (Int) -> Void
    let onWeightChange: (Double) -> Void
    let onRemove: () -> Void

    private var repsColor: Color {
        guard let min = targetRepMin, let max = targetRepMax else { return .white }
        if reps >= max { return DesignSystem.Colors.warning }
        if reps >= min { return DesignSystem.Colors.tint }
        return Color.white.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 8) {
            if canRemove {
                Button {
                    HapticManager.shared.light()
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DesignSystem.Colors.destructive)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("set.delete_accessibility".localized(index + 1))
            }

            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 14)

            HStack(spacing: 6) {
                valueStepper(
                    value: Double(reps),
                    step: 1,
                    minimum: 1,
                    maximum: 100,
                    fieldWidth: 26,
                    unit: "set.reps_unit".localized,
                    valueColor: repsColor,
                    keyboard: .numberPad,
                    fieldBinding: Binding(
                        get: { Double(reps) },
                        set: { onRepsChange(Swift.max(1, Int($0))) }
                    ),
                    onStep: { onRepsChange(Int($0)) }
                )

                Spacer(minLength: 2)

                valueStepper(
                    value: weight,
                    step: 2.5,
                    minimum: 0,
                    maximum: 999,
                    fieldWidth: 42,
                    unit: "set.weight_unit".localized,
                    valueColor: .white,
                    keyboard: .decimalPad,
                    fieldBinding: Binding(
                        get: { weight },
                        set: { onWeightChange(Swift.max(0, $0)) }
                    ),
                    onStep: onWeightChange
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("accessibility.set.label".localized(index + 1, reps, weight))
    }

    /// − [typable value] unit + — the number is a `TextField` styled as text, so
    /// exact values stay reachable without leaving the row.
    @ViewBuilder
    private func valueStepper(
        value: Double,
        step: Double,
        minimum: Double,
        maximum: Double,
        fieldWidth: CGFloat,
        unit: String,
        valueColor: Color,
        keyboard: UIKeyboardType,
        fieldBinding: Binding<Double>,
        onStep: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            stepButton(symbol: "minus", isEnabled: value > minimum) {
                onStep(Swift.max(minimum, value - step))
            }

            HStack(spacing: 2) {
                TextField("", value: fieldBinding, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .focused(valueFocus)
                    .selectAllOnFocus()
                    .frame(width: fieldWidth)

                Text(unit)
                    .foregroundStyle(valueColor.opacity(0.75))
            }
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(valueColor)
            .lineLimit(1)

            stepButton(symbol: "plus", isEnabled: value < maximum) {
                onStep(Swift.min(maximum, value + step))
            }
        }
    }

    private func stepButton(symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? DesignSystem.Colors.tint : DesignSystem.Colors.textDisabled)
                .frame(width: 26, height: 26)
                .background(DesignSystem.Colors.tint.opacity(isEnabled ? 0.16 : 0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Set list

/// The "SÄTZE" block of an exercise card: rows, the apply-to-all banner for the
/// most recently edited row, and the inline add-set button.
struct RoutineSetsEditor<SetType: AlternativeEditableSet>: View {
    let sets: [SetType]
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
