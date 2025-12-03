//
//  FullScreenValueRow.swift
//  GymStreakWatch Watch App
//
//  Created by Claude Code
//

import SwiftUI
import WatchKit

/// A full-screen value editor row with large +/- buttons optimized for Apple Watch
/// Designed for single-task focus with no scrolling conflicts
struct FullScreenValueRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let step: Double
    let range: ClosedRange<Double>
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Label
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFocused ? .blue : .secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            // Control row
            HStack(spacing: 8) {
                // Minus button - compact but tappable
                Button {
                    decreaseValue()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)
                .opacity(value <= range.lowerBound ? 0.4 : 1.0)
                .frame(width: 40, height: 40)

                // Value - tappable to focus for Digital Crown
                Button {
                    onTap()
                } label: {
                    VStack(spacing: 1) {
                        Text(formatValue(value))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()

                        Text(unit)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 70)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isFocused ? Color.blue.opacity(0.15) : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isFocused ? Color.blue : Color.gray.opacity(0.2),
                            lineWidth: isFocused ? 2 : 1.5
                        )
                }

                // Plus button - compact but tappable
                Button {
                    increaseValue()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
                .opacity(value >= range.upperBound ? 0.4 : 1.0)
                .frame(width: 40, height: 40)
            }
            .foregroundStyle(isFocused ? .blue : .primary)

            // Crown hint - only when focused, more compact
            if isFocused {
                HStack(spacing: 3) {
                    Image(systemName: "crown")
                        .font(.system(size: 9))
                    Text("Turn Crown")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.blue)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
        .accessibilityHint(isFocused ? "Adjustable. Rotate crown or swipe up and down to change value." : "Double tap to focus and adjust value")
        .accessibilityValue("\(formatValue(value))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                increaseValue()
            case .decrement:
                decreaseValue()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Actions

    private func increaseValue() {
        let newValue = min(value + step, range.upperBound)
        if newValue != value {
            value = newValue
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func decreaseValue() {
        let newValue = max(value - step, range.lowerBound)
        if newValue != value {
            value = newValue
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
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
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    FullScreenValueRow(
                        label: "WEIGHT",
                        value: $weight,
                        unit: "lbs",
                        step: 5,
                        range: 0...999,
                        isFocused: focusedField == .weight,
                        onTap: { focusedField = .weight }
                    )

                    FullScreenValueRow(
                        label: "REPS",
                        value: $reps,
                        unit: "reps",
                        step: 1,
                        range: 0...100,
                        isFocused: focusedField == .reps,
                        onTap: { focusedField = .reps }
                    )
                }
                .padding()
            }
        }
    }

    return PreviewWrapper()
}
