//
//  ValueStepperView.swift
//  GymStreakWatch Watch App
//
//  Created by Claude Code
//

import SwiftUI
import WatchKit

/// A reusable stepper component for adjusting numeric values on Apple Watch
/// Combines touch +/- buttons with Digital Crown support for flexible input
struct ValueStepperView: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let isFocused: Bool
    let onFocusTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Label indicator
            Text(label)
                .font(.caption2)
                .foregroundStyle(isFocused ? .blue : .secondary)
                .fontWeight(isFocused ? .semibold : .regular)

            HStack(spacing: 12) {
                // Minus button
                Button {
                    adjustValue(by: -step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)
                .opacity(value <= range.lowerBound ? 0.4 : 1.0)

                // Value display (tappable to focus)
                Button {
                    onFocusTap()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(formatValue(value))")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()

                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFocused ? Color.blue.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isFocused ? Color.blue : Color.gray.opacity(0.3),
                            lineWidth: 2
                        )
                )

                // Plus button
                Button {
                    adjustValue(by: step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
                .opacity(value >= range.upperBound ? 0.4 : 1.0)
            }
            .foregroundStyle(isFocused ? .blue : .primary)

            // Crown hint (only shown when focused)
            if isFocused {
                Text("scroll crown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .focusable(isFocused)
        .digitalCrownRotation(
            $value,
            from: range.lowerBound,
            through: range.upperBound,
            by: step,
            sensitivity: step == 1 ? .low : .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). \(formatValue(value)) \(unit)")
        .accessibilityHint(isFocused ? "Adjustable. Swipe up or down to change value." : "Double tap to adjust.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustValue(by: step)
            case .decrement:
                adjustValue(by: -step)
            @unknown default:
                break
            }
        }
    }

    /// Adjusts the value by the given delta, clamped to the valid range
    private func adjustValue(by delta: Double) {
        let newValue = (value + delta).clamped(to: range)
        if newValue != value {
            value = newValue
            WKInterfaceDevice.current().play(.click)
        }
    }

    /// Formats the value for display (removes decimal if it's a whole number)
    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Helper Extension

extension Comparable {
    /// Clamps a value to the given range
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var weight: Double = 135
        @State private var reps: Double = 10
        @State private var focusedField: Field = .weight

        enum Field {
            case weight, reps
        }

        var body: some View {
            VStack(spacing: 16) {
                ValueStepperView(
                    label: "WEIGHT",
                    value: $weight,
                    unit: "lbs",
                    range: 0...999,
                    step: 5,
                    isFocused: focusedField == .weight,
                    onFocusTap: { focusedField = .weight }
                )

                ValueStepperView(
                    label: "REPS",
                    value: $reps,
                    unit: "reps",
                    range: 0...100,
                    step: 1,
                    isFocused: focusedField == .reps,
                    onFocusTap: { focusedField = .reps }
                )
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
