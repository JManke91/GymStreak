//
//  RepRangeConfigView.swift
//  GymStreak
//

import SwiftUI

struct RepRangeConfigView: View {
    @Binding var targetRepMin: Int?
    @Binding var targetRepMax: Int?
    @Binding var isExpanded: Bool
    var onRepRangeChange: ((Int?, Int?) -> Void)?

    @State private var editingMin: Int = 8
    @State private var editingMax: Int = 12

    private var isConfigured: Bool {
        targetRepMin != nil && targetRepMax != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button {
                withAnimation(.snappy(duration: 0.35)) {
                    if isConfigured {
                        isExpanded.toggle()
                    } else {
                        // Enable with defaults and expand
                        editingMin = 8
                        editingMax = 12
                        targetRepMin = 8
                        targetRepMax = 12
                        onRepRangeChange?(8, 12)
                        isExpanded = true
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: isConfigured ? "target" : "scope")
                            .font(.subheadline)
                            .foregroundStyle(isConfigured ? DesignSystem.Colors.tint : .secondary)

                        if isConfigured, let min = targetRepMin, let max = targetRepMax {
                            Text("rep_range.target".localized(min, max))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DesignSystem.Colors.tint)
                        } else {
                            Text("rep_range.set_goal".localized)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isConfigured ? DesignSystem.Colors.tint.opacity(0.1) : Color.secondary.opacity(0.1))
                    )

                    Spacer()

                    if isConfigured {
                        Image(systemName: "chevron.down")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded configuration
            if isExpanded && isConfigured {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.top, 8)

                    // Min reps stepper
                    HorizontalStepper(
                        title: "rep_range.min".localized,
                        value: $editingMin,
                        range: 1...99,
                        step: 1
                    ) { newValue in
                        // Ensure max is always > min
                        if editingMax <= newValue {
                            editingMax = newValue + 1
                            targetRepMax = editingMax
                        }
                        targetRepMin = newValue
                        onRepRangeChange?(newValue, editingMax)
                    }

                    // Max reps stepper
                    HorizontalStepper(
                        title: "rep_range.max".localized,
                        value: $editingMax,
                        range: (editingMin + 1)...100,
                        step: 1
                    ) { newValue in
                        targetRepMax = newValue
                        onRepRangeChange?(editingMin, newValue)
                    }

                    // Quick presets
                    HStack(spacing: 8) {
                        presetButton(label: "4-6", subtitle: "rep_range.strength".localized, min: 4, max: 6)
                        presetButton(label: "8-12", subtitle: "rep_range.hypertrophy".localized, min: 8, max: 12)
                        presetButton(label: "12-15", subtitle: "rep_range.endurance".localized, min: 12, max: 15)
                    }

                    // Remove rep goal button
                    Button {
                        withAnimation(.snappy(duration: 0.35)) {
                            targetRepMin = nil
                            targetRepMax = nil
                            isExpanded = false
                            onRepRangeChange?(nil, nil)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .font(.subheadline)
                            Text("rep_range.clear".localized)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isExpanded && isConfigured ? DesignSystem.Colors.tint.opacity(0.05) : Color.clear)
        )
        .onAppear {
            if let min = targetRepMin {
                editingMin = min
            }
            if let max = targetRepMax {
                editingMax = max
            }
        }
    }

    private func presetButton(label: String, subtitle: String, min: Int, max: Int) -> some View {
        let isSelected = editingMin == min && editingMax == max
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                editingMin = min
                editingMax = max
                targetRepMin = min
                targetRepMax = max
                onRepRangeChange?(min, max)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? DesignSystem.Colors.tint : DesignSystem.Colors.tint.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}
