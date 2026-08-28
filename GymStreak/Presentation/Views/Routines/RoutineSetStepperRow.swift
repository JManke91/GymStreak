//
//  RoutineSetStepperRow.swift
//  GymStreak
//
//  One row of the always-editable set list: index badge, reps stepper, weight
//  stepper, remove button. Split out of RoutineSetsEditor when the weight-unit
//  conversion pushed that file past the 300-line convention — "one set row" and
//  "the set list plus its apply-to-all banner" are two jobs.
//

import SwiftUI

/// Value-typed set row: takes plain numbers, reports edits through callbacks.
/// Keeping models out of the row avoids a relationship read per row.
struct RoutineSetStepperRow: View {
    let index: Int
    let reps: Int
    /// Canonical kilograms, as stored.
    let weight: Double
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var canRemove: Bool = true
    /// Shared "a set value is being typed" flag driving the screen's Done bar.
    var valueFocus: FocusState<Bool>.Binding
    let onRepsChange: (Int) -> Void
    /// Called with canonical kilograms.
    let onWeightChange: (Double) -> Void
    let onRemove: () -> Void

    @Environment(\.weightUnit) private var weightUnit
    /// `weight` expressed in `weightUnit` — the value the field and the ±
    /// buttons actually edit. `weightDisplayMirror` owns the invariant that
    /// keeps it and the canonical kilograms in step.
    @State private var displayWeight: Double = 0

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
                    value: Binding(
                        get: { Double(reps) },
                        set: { onRepsChange(Swift.max(1, Int($0))) }
                    ),
                    step: 1,
                    minimum: 1,
                    maximum: 100,
                    fieldWidth: 26,
                    unit: "set.reps_unit".localized,
                    valueColor: repsColor,
                    keyboard: .numberPad,
                    format: Self.repsStyle
                )

                Spacer(minLength: 2)

                valueStepper(
                    // The field edits display space; the mirror below converts,
                    // snaps and clamps before anything reaches the store.
                    value: $displayWeight,
                    step: weightUnit.coarseIncrement,
                    minimum: 0,
                    maximum: weightUnit.maximumDisplay,
                    fieldWidth: 42,
                    unit: WeightFormatting.unitWord(weightUnit),
                    valueColor: .white,
                    keyboard: .decimalPad,
                    format: WeightFormatting.inputStyle(for: weightUnit)
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .weightDisplayMirror(
            // The setter is the row's own report-upward hook, so the mirror's
            // separate `onUpdate` would fire a second, duplicate write.
            // A closure literal, not `set: onWeightChange`: `Binding`'s setter
            // is `@Sendable`, and handing it a stored non-`Sendable` closure
            // property warns. The literal is main-actor-isolated (SE-0461).
            kilograms: Binding(get: { weight }, set: { onWeightChange($0) }),
            displayValue: $displayWeight
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("accessibility.set.label".localized(
            index + 1,
            reps,
            WeightFormatting.spokenLabel(weight, in: weightUnit)
        ))
    }

    /// Reps are whole numbers; the field is a `Double` only because it shares
    /// the weight field's chrome.
    private static let repsStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)

    /// − [typable value] unit + — the number is a `TextField` styled as text, so
    /// exact values stay reachable without leaving the row. `minimum`/`maximum`/
    /// `step` are in the same space as `value`: display units for the weight
    /// field, plain counts for reps.
    @ViewBuilder
    private func valueStepper(
        value: Binding<Double>,
        step: Double,
        minimum: Double,
        maximum: Double,
        fieldWidth: CGFloat,
        unit: String,
        valueColor: Color,
        keyboard: UIKeyboardType,
        format: FloatingPointFormatStyle<Double>
    ) -> some View {
        HStack(spacing: 5) {
            stepButton(symbol: "minus", isEnabled: value.wrappedValue > minimum) {
                value.wrappedValue = Swift.max(minimum, value.wrappedValue - step)
            }

            HStack(spacing: 2) {
                TextField("", value: value, format: format)
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

            stepButton(symbol: "plus", isEnabled: value.wrappedValue < maximum) {
                value.wrappedValue = Swift.min(maximum, value.wrappedValue + step)
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
