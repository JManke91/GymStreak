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

/// A weight stepper with decimal support
struct OnyxWeightStepper: View {
    let title: String
    @Binding var weight: Double
    let increment: Double

    init(
        title: String = "Weight (kg)",
        weight: Binding<Double>,
        increment: Double = 0.25
    ) {
        self.title = title
        self._weight = weight
        self.increment = increment
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
                let newWeight = max(0, weight - increment)
                weight = newWeight
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(weight <= 0 ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(weight <= 0)

            // Editable weight field
            TextField("0.0", value: $weight, format: .number.precision(.fractionLength(0...2)))
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
                weight += increment
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
