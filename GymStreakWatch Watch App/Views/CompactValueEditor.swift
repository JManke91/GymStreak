//
//  CompactValueEditor.swift
//  GymStreakWatch Watch App
//
//  Compact value editor optimized for side-by-side layout
//

import SwiftUI
import WatchKit

struct CompactValueEditor: View {
    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    let label: String
    @Binding var value: Double
    let unit: String
    let icon: String
    let step: Double
    let range: ClosedRange<Double>
    let isFocused: Bool
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    // Optional set info - shown when NOT focused
    let currentSetIndex: Int?
    let totalSets: Int?

    @State private var lastHapticIntValue: Int = 0
    @State private var lastHapticStepBoundary: Int = 0

    var body: some View {
        VStack(spacing: 3) {
            // Compact stepper buttons (only show when focused)
            if isFocused {
                HStack(spacing: 8) {
                    // Minus button
                    Button {
                        onDecrement()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(OnyxWatch.Colors.tint)
                    .disabled(value <= range.lowerBound)
                    .opacity(value <= range.lowerBound ? 0.4 : 1.0)

                    // Plus button
                    Button {
                        onIncrement()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(OnyxWatch.Colors.tint)
                    .disabled(value >= range.upperBound)
                    .opacity(value >= range.upperBound ? 0.4 : 1.0)
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            // Set indicator - only show on NON-focused editor'
            // TODO: 🚧 - replace with workout metrics
            if !isFocused, let heartRate = viewModel.heartRate, let calories = viewModel.activeCalories {
                WorkoutMetricsView(heartRate: heartRate, calories: calories, size: .small)
            }

            // Icon + Label (compact header)
//            HStack(spacing: 3) {
//                Image(systemName: icon)
//                    .font(.system(size: 9, weight: .semibold))
//                Text(label)
//                    .font(.system(size: 9, weight: .semibold))
//                    .textCase(.uppercase)
//            }
//            .foregroundStyle(isFocused ? .blue : .secondary)
//            .tracking(0.4)

            // Tappable value area
            Button {
                onTap()
            } label: {
                VStack(spacing: 1) {
                    // Main number value (reduced from 32pt)
                    Text(formatValue(value))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    // Unit label
                    HStack {
                        Image(systemName: icon)
                                            .font(.system(size: 9, weight: .semibold))

                        Text(unit)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }

                .frame(height: 40) // Fixed height for consistency
                .padding(5)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
//            .frame(height: 60)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused ? OnyxWatch.Colors.tint.opacity(0.12) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? OnyxWatch.Colors.tint : OnyxWatch.Colors.textSecondary.opacity(0.25),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            }
//            .frame(height: 60)
        }
        .focusable(isFocused)
        .scrollIndicators(.hidden)
//        .frame(height: 60)
//        .digitalCrownRotation(
//            $value,
//            from: range.lowerBound,
//            through: range.upperBound,
//            by: step,
//            sensitivity: .medium,
//            isContinuous: false,
//            isHapticFeedbackEnabled: false
//        )
//        .onChange(of: value) { oldValue, newValue in
//            // Provide haptic feedback only when crossing meaningful boundaries
//            if step == 1 {
//                // Integer steps (reps): only haptic when integer value actually changes
//                let currentIntValue = Int(round(newValue))
//                if currentIntValue != lastHapticIntValue {
//                    WKInterfaceDevice.current().play(.click)
//                    lastHapticIntValue = currentIntValue
//                }
//            } else {
//                // Multi-unit steps (weight): haptic every N units
//                let currentStepBoundary = Int(newValue / step)
//                if currentStepBoundary != lastHapticStepBoundary {
//                    WKInterfaceDevice.current().play(.click)
//                    lastHapticStepBoundary = currentStepBoundary
//                }
//            }
//        }
//        .onAppear {
//            if step == 1 {
//                lastHapticIntValue = Int(round(value))
//            } else {
//                lastHapticStepBoundary = Int(value / step)
//            }
//        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). \(formatValue(value)) \(unit)")
        .accessibilityValue("\(formatValue(value))")
//        .accessibilityAdjustableAction { direction in
//            switch direction {
//            case .increment: onIncrement()
//            case .decrement: onDecrement()
//            @unknown default: break
//            }
//        }
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

//#Preview {
//    struct PreviewWrapper: View {
//        @State private var weight: Double = 135
//        @State private var reps: Double = 10
//        @State private var focusedField: Field = .weight
//
//        enum Field {
//            case weight, reps
//        }
//
//        var body: some View {
//            ZStack {
//                Color.black.ignoresSafeArea()
//
//                HStack(spacing: 12) {
//                    CompactValueEditor(
//                        label: "WEIGHT",
//                        value: $weight,
//                        unit: "lb",
//                        icon: "scalemass.fill",
//                        step: 5,
//                        range: 0...999,
//                        isFocused: focusedField == .weight,
//                        onTap: { focusedField = .weight },
//                        onIncrement: { weight = min(999, weight + 5) },
//                        onDecrement: { weight = max(0, weight - 5) },
//                        currentSetIndex: 1,
//                        totalSets: 3
//                    )
//
//                    CompactValueEditor(
//                        label: "REPS",
//                        value: $reps,
//                        unit: "reps",
//                        icon: "repeat",
//                        step: 1,
//                        range: 0...100,
//                        isFocused: focusedField == .reps,
//                        onTap: { focusedField = .reps },
//                        onIncrement: { reps = min(100, reps + 1) },
//                        onDecrement: { reps = max(0, reps - 1) },
//                        currentSetIndex: 1,
//                        totalSets: 3
//                    )
//                }
//                .padding()
//            }
//        }
//    }
//
//    return PreviewWrapper()
//}
