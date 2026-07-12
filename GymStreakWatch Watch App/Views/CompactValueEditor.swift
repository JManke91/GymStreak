//
//  CompactValueEditor.swift
//  GymStreakWatch Watch App
//
//  Value card for the set editor's side-by-side weight/reps layout.
//  The focused card gets the dark-green active treatment; the shared
//  stepper buttons in FullScreenSetEditorView adjust the focused value.
//

import SwiftUI

struct CompactValueEditor: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let icon: String
    let isFocused: Bool
    let onTap: () -> Void

    private let metrics = WorkoutScreenMetrics.current

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 1.5) {
                Text(formatValue(value))
                    .font(.system(size: metrics.valueFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OnyxWatch.Colors.textPrimary)

                HStack(spacing: 2.5) {
                    Image(systemName: icon)
                        .font(.system(size: metrics.valueUnitSize, weight: .semibold))
                    Text(unit)
                        .font(.system(size: metrics.valueUnitSize, weight: .medium))
                }
                .foregroundStyle(OnyxWatch.Colors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.valueCardHeight)
            .background {
                RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous)
                    .fill(isFocused ? OnyxWatch.Colors.surfaceCardActive : OnyxWatch.Colors.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? OnyxWatch.Colors.accentGreen : OnyxWatch.Colors.strokeSubtle,
                        lineWidth: isFocused ? 1 : 0.75
                    )
            }
            .shadow(
                color: isFocused ? OnyxWatch.Colors.accentGreen.opacity(0.22) : .clear,
                radius: 8
            )
            .contentShape(RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label). \(formatValue(value)) \(unit)")
        .accessibilityValue("\(formatValue(value))")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
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
        @State private var focused = 0

        var body: some View {
            ZStack {
                OnyxWatch.Colors.background.ignoresSafeArea()

                HStack(spacing: 6.5) {
                    CompactValueEditor(
                        label: "WEIGHT",
                        value: $weight,
                        unit: "kg",
                        icon: "scalemass.fill",
                        isFocused: focused == 0,
                        onTap: { focused = 0 }
                    )

                    CompactValueEditor(
                        label: "REPS",
                        value: $reps,
                        unit: "reps",
                        icon: "repeat",
                        isFocused: focused == 1,
                        onTap: { focused = 1 }
                    )
                }
                .padding(.horizontal, 8)
            }
        }
    }

    return PreviewWrapper()
}
