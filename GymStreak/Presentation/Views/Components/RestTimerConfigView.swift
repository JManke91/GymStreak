//
//  RestTimerConfigView.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI

struct RestTimerConfigView: View {
    @Binding var restTime: TimeInterval
    @Binding var isExpanded: Bool
    var showToggle: Bool = true  // Whether rest timer can be toggled on/off
    var onRestTimeChange: ((TimeInterval) -> Void)?

    @State private var lastRestTime: TimeInterval = 60  // Remember last value when toggling

    private var isRestTimerEnabled: Bool {
        restTime > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button {
                withAnimation(.snappy(duration: 0.35)) {
                    if isRestTimerEnabled {
                        // If enabled, just toggle expand/collapse
                        isExpanded.toggle()
                    } else {
                        // If disabled, enable it and expand
                        enableRestTimer()
                    }
                }

                // Haptic feedback
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: isRestTimerEnabled ? "timer" : "timer.slash")
                            .font(.subheadline)
                            .foregroundStyle(isRestTimerEnabled ? DesignSystem.Colors.tint : .secondary)

                        if isRestTimerEnabled {
                            Text("rest_timer.rest".localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(TimeFormatting.formatRestTime(restTime))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DesignSystem.Colors.tint)
                        } else {
                            Text("rest_timer.set".localized)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRestTimerEnabled ? DesignSystem.Colors.tint.opacity(0.1) : Color.secondary.opacity(0.1))
                    )

                    Spacer()

                    if isRestTimerEnabled {
                        Image(systemName: "chevron.down")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRestTimerEnabled ? "rest_timer.config.enabled".localized(TimeFormatting.formatRestTime(restTime)) : "rest_timer.config.disabled".localized)
            .accessibilityHint(isExpanded ? "accessibility.set.hint.expanded".localized : "Tap to enable and configure")
            .accessibilityAddTraits(.isButton)

            // Expanded configuration
            if isExpanded && isRestTimerEnabled {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.top, 8)

                    // Slider
                    Slider(value: Binding(
                        get: { restTime },
                        set: { newValue in
                            let rounded = (newValue / 30).rounded() * 30
                            restTime = rounded
                            lastRestTime = rounded  // Remember for re-enabling
                            onRestTimeChange?(rounded)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    ), in: 0...300, step: 30)
                    .tint(DesignSystem.Colors.tint)

                    // Quick preset buttons
                    HStack(spacing: 8) {
                        ForEach([30.0, 60.0, 90.0, 120.0], id: \.self) { preset in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    restTime = preset
                                    lastRestTime = preset  // Remember for re-enabling
                                    onRestTimeChange?(preset)
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Text("\(Int(preset))s")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(restTime == preset ? .white : DesignSystem.Colors.tint)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(restTime == preset ? DesignSystem.Colors.tint : DesignSystem.Colors.tint.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Disable rest timer button (only show if showToggle is true)
                    if showToggle {
                        Button {
                            disableRestTimer()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack {
                                Image(systemName: "timer.slash")
                                    .font(.subheadline)
                                Text("rest_timer.disable".localized)
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
                .fill(isExpanded && isRestTimerEnabled ? DesignSystem.Colors.tint.opacity(0.05) : Color.clear)
        )
        .onAppear {
            // Initialize lastRestTime if restTime is already set
            if restTime > 0 {
                lastRestTime = restTime
            }
        }
    }

    private func enableRestTimer() {
        // Enable: restore last value or use default
        restTime = lastRestTime > 0 ? lastRestTime : 60
        isExpanded = true  // Auto-expand when enabling
        onRestTimeChange?(restTime)
    }

    private func disableRestTimer() {
        withAnimation(.snappy(duration: 0.35)) {
            // Disable: store current value and set to 0
            lastRestTime = restTime
            restTime = 0
            isExpanded = false
            onRestTimeChange?(0)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Disabled state
        RestTimerConfigView(
            restTime: .constant(0),
            isExpanded: .constant(false)
        )

        // Enabled, collapsed
        RestTimerConfigView(
            restTime: .constant(90),
            isExpanded: .constant(false)
        )

        // Enabled, expanded
        RestTimerConfigView(
            restTime: .constant(90),
            isExpanded: .constant(true)
        )

        // Workout mode (no toggle, just expand/collapse)
        RestTimerConfigView(
            restTime: .constant(60),
            isExpanded: .constant(true),
            showToggle: false
        )
    }
    .padding()
}
