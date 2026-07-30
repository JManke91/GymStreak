//
//  RoutineParameterEditors.swift
//  GymStreak
//
//  The inline editors an exercise card's parameter chips open directly beneath
//  the chip strip: rest time and rep-range goal. Replaces the former
//  RestTimerConfigView / RepRangeConfigView blocks inside the expanded card.
//

import SwiftUI

// MARK: - Compact stepper

/// − value + control sized for inline editors and set rows. Works on `Double`
/// so it serves both whole-number (reps) and fractional (weight, seconds) values.
struct CompactStepper: View {
    let value: Double
    var step: Double = 1
    var minimum: Double = 0
    var maximum: Double = 9999
    let format: (Double) -> String
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            button(direction: -1, symbol: "minus", isEnabled: value > minimum)

            Text(format(value))
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            button(direction: 1, symbol: "plus", isEnabled: value < maximum)
        }
    }

    private func button(direction: Double, symbol: String, isEnabled: Bool) -> some View {
        Button {
            let next = min(maximum, max(minimum, value + direction * step))
            guard next != value else { return }
            HapticManager.shared.light()
            onChange(next)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? DesignSystem.Colors.tint : DesignSystem.Colors.textDisabled)
                .frame(width: 26, height: 26)
                .background(DesignSystem.Colors.tint.opacity(isEnabled ? 0.16 : 0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Editor shell

/// Tinted container the chip editors open into.
struct ParameterEditorPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.tint.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignSystem.Colors.tint.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Rest time editor

/// Presets + fine stepper + enable/disable, opened by the "Pause" chip.
/// A rest time of 0 means the timer is off.
struct RestTimeInlineEditor: View {
    let restTime: TimeInterval
    let onChange: (TimeInterval) -> Void

    private static let presets: [TimeInterval] = [60, 90, 120, 150]
    private var isEnabled: Bool { restTime > 0 }

    var body: some View {
        ParameterEditorPanel {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(Self.presets, id: \.self) { preset in
                            presetButton(preset)
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 1, height: 22)

                    CompactStepper(
                        value: restTime,
                        step: 15,
                        minimum: 0,
                        maximum: 600,
                        format: { TimeFormatting.formatRestTime($0) },
                        onChange: onChange
                    )
                }
                .opacity(isEnabled ? 1 : 0.4)
                .disabled(!isEnabled)

                Button {
                    HapticManager.shared.light()
                    onChange(isEnabled ? 0 : 90)
                } label: {
                    Text(isEnabled ? "rest_timer.disable".localized : "rest_timer.enable".localized)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isEnabled ? Color.white.opacity(0.6) : DesignSystem.Colors.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isEnabled ? Color.white.opacity(0.05) : DesignSystem.Colors.tint.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isEnabled ? Color.white.opacity(0.07) : DesignSystem.Colors.tint.opacity(0.4), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presetButton(_ preset: TimeInterval) -> some View {
        let isSelected = restTime == preset
        return Button {
            HapticManager.shared.light()
            onChange(preset)
        } label: {
            Text(TimeFormatting.formatRestTime(preset))
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSelected ? DesignSystem.Colors.tint : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rep range editor

/// Preset segments + a custom min/max mode, opened by the "Ziel" chip.
/// `nil`/`nil` means no rep goal is set.
struct RepRangeInlineEditor: View {
    let targetRepMin: Int?
    let targetRepMax: Int?
    /// New (min, max), or (nil, nil) to clear the goal.
    let onChange: (Int?, Int?) -> Void

    static let presets: [(min: Int, max: Int)] = [(4, 6), (8, 12), (12, 15)]

    @State private var customMode = false

    private var matchesPreset: Bool {
        guard let min = targetRepMin, let max = targetRepMax else { return false }
        return Self.presets.contains { $0.min == min && $0.max == max }
    }

    private var isCustom: Bool {
        customMode || (targetRepMin != nil && !matchesPreset)
    }

    var body: some View {
        ParameterEditorPanel {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(Self.presets, id: \.min) { preset in
                            segment(
                                title: "\(preset.min)–\(preset.max)",
                                isSelected: !isCustom && targetRepMin == preset.min && targetRepMax == preset.max
                            ) {
                                customMode = false
                                onChange(preset.min, preset.max)
                            }
                        }
                        segment(title: "rep_range.custom".localized, isSelected: isCustom) {
                            customMode = true
                            if targetRepMin == nil || targetRepMax == nil {
                                onChange(6, 10)
                            }
                        }
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Button {
                        HapticManager.shared.light()
                        customMode = false
                        onChange(nil, nil)
                    } label: {
                        Text("rep_range.no_goal".localized)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }

                if isCustom, let min = targetRepMin, let max = targetRepMax {
                    Divider()
                        .overlay(Color.white.opacity(0.07))
                        .padding(.top, 10)

                    HStack(alignment: .bottom, spacing: 10) {
                        boundColumn(title: "rep_range.min".localized) {
                            CompactStepper(
                                value: Double(min),
                                minimum: 1,
                                maximum: 99,
                                format: { "\(Int($0))" },
                                onChange: { newValue in
                                    let newMin = Int(newValue)
                                    onChange(newMin, Swift.max(newMin, max))
                                }
                            )
                        }

                        Text("–")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.25))
                            .padding(.bottom, 5)

                        boundColumn(title: "rep_range.max".localized) {
                            CompactStepper(
                                value: Double(max),
                                minimum: Double(min),
                                maximum: 100,
                                format: { "\(Int($0))" },
                                onChange: { onChange(min, Int($0)) }
                            )
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .animation(DesignSystem.Animation.spring, value: isCustom)
    }

    private func segment(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.light()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? DesignSystem.Colors.textOnTint : Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSelected ? DesignSystem.Colors.tint : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func boundColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var rest: TimeInterval = 90
        @State private var repMin: Int? = 8
        @State private var repMax: Int? = 12
        @State private var open: String? = "pause"

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        ParameterChipButton(
                            icon: "timer",
                            label: "Pause",
                            value: rest > 0 ? TimeFormatting.formatRestTime(rest) : "aus",
                            isActive: open == "pause"
                        ) { open = open == "pause" ? nil : "pause" }

                        ParameterChipButton(
                            icon: "target",
                            label: "Ziel",
                            value: "8–12 Wdh.",
                            isActive: open == "reps"
                        ) { open = open == "reps" ? nil : "reps" }
                        Spacer()
                    }

                    if open == "pause" {
                        RestTimeInlineEditor(restTime: rest) { rest = $0 }
                    } else if open == "reps" {
                        RepRangeInlineEditor(targetRepMin: repMin, targetRepMax: repMax) { repMin = $0; repMax = $1 }
                    }
                }
                .padding()
            }
        }
    }
    return PreviewWrapper()
}
