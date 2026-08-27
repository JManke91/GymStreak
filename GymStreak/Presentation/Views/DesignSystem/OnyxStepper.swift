//
//  OnyxStepper.swift
//  GymStreak
//
//  +/- stepper for reps/weight values in the Onyx Design System
//

import SwiftUI

/// A horizontal stepper with Onyx Design System styling
struct OnyxStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    init(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int> = 1...100,
        step: Int = 1
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .fixedSize()

            Spacer()

            // Minus button
            Button {
                guard value > range.lowerBound else { return }
                value -= step
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(value <= range.lowerBound ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(value <= range.lowerBound)

            // Value display
            Text("\(value)")
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(minWidth: 44)
                .contentShape(Rectangle())

            // Plus button
            Button {
                guard value < range.upperBound else { return }
                value += step
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(value >= range.upperBound ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(value >= range.upperBound)
        }
    }
}

/// A weight stepper with decimal support, in the Onyx Design System styling.
///
/// Same contract as `WeightInput`: the binding is canonical kilograms and the
/// field edits a display-space mirror of it, owned by `weightDisplayMirror`.
struct OnyxWeightStepper: View {
    let title: String
    /// Canonical kilograms.
    @Binding var weight: Double

    @Environment(\.weightUnit) private var weightUnit
    /// `weight` expressed in `weightUnit` — the value the field actually edits.
    @State private var displayValue: Double = 0

    init(
        title: String,
        weight: Binding<Double>
    ) {
        self.title = title
        self._weight = weight
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .fixedSize()

            Spacer()

            // Minus button
            Button {
                displayValue = max(0, displayValue - weightUnit.fineIncrement)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(displayValue <= 0 ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(displayValue <= 0)

            // Editable weight field, in the displayed unit
            TextField("0", value: $displayValue, format: WeightFormatting.inputStyle(for: weightUnit))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 70)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(DesignSystem.Colors.input)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM))
                .selectAllOnFocus()

            // Plus button
            Button {
                displayValue = min(displayValue + weightUnit.fineIncrement, weightUnit.maximumDisplay)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .weightDisplayMirror(kilograms: $weight, displayValue: $displayValue)
    }
}

// MARK: - Previews

#Preview("Steppers") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 24) {
            OnyxStepper(title: "Reps", value: .constant(10), range: 1...100)

            OnyxWeightStepper(title: "Weight (kg)", weight: .constant(100.0))
        }
        .padding()
    }
}
