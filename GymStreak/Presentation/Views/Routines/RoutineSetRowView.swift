//
//  RoutineSetRowView.swift
//  GymStreak
//
//  Expandable set row of the redesigned RoutineDetailView (extracted from
//  RoutineDetailComponents to keep files under the size limit).
//

import SwiftUI

// MARK: - Expandable set row

struct RoutineSetRowView: View {
    let set: ExerciseSet
    let index: Int
    let isExpanded: Bool
    @Binding var editingReps: Int
    @Binding var editingWeight: Double
    let initialReps: Int
    let initialWeight: Double
    let hasMultipleSets: Bool
    let repsBannerDismissed: Bool
    let weightBannerDismissed: Bool
    let totalSets: Int
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    let onTap: () -> Void
    let onUpdate: (Int, Double) -> Void
    let onApplyRepsToAll: () -> Void
    let onApplyWeightToAll: () -> Void
    let onDismissRepsBanner: () -> Void
    let onDismissWeightBanner: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteSetAlert = false

    private var repsChanged: Bool {
        editingReps != initialReps
    }

    private var weightChanged: Bool {
        editingWeight != initialWeight
    }

    private var repRangeColor: Color {
        guard let min = targetRepMin, let max = targetRepMax else { return .white }
        if set.reps >= max {
            return .orange
        } else if set.reps >= min {
            return DesignSystem.Colors.tint
        } else {
            return Color.white.opacity(0.6)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Set header
            Button(action: {
                HapticManager.shared.light()
                onTap()
            }) {
                HStack(spacing: 12) {
                    // Set number badge
                    Text("\(index + 1)")
                        .font(.system(size: 11.5, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(width: 24, height: 24)
                        .background(DesignSystem.Colors.tint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("set.reps".localized(set.reps))
                            .foregroundStyle(repRangeColor)
                        Text("×")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.35))
                        Text("set.weight".localized(set.weight))
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .monospacedDigit()

                    // Rep range progress badge
                    if let max = targetRepMax {
                        Text("\(set.reps)/\(max)")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(repRangeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(repRangeColor.opacity(0.1), in: Capsule())
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(isExpanded ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                        .foregroundStyle(isExpanded ? DesignSystem.Colors.tint : Color.white.opacity(0.35))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(DesignSystem.Animation.spring, value: isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("accessibility.set.label".localized(index + 1, set.reps, set.weight))
            .accessibilityHint(isExpanded ? "accessibility.set.hint.expanded".localized : "accessibility.set.hint.collapsed".localized)
            .accessibilityAddTraits(.isButton)

            // Expanded edit form
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(spacing: 16) {
                    // Reps input with contextual banner
                    VStack(spacing: 8) {
                        HorizontalStepper(
                            title: "set.reps_label".localized,
                            value: $editingReps,
                            range: 1...100,
                            step: 1
                        ) { newValue in
                            onUpdate(newValue, editingWeight)
                        }

                        if hasMultipleSets && repsChanged && !repsBannerDismissed {
                            ApplyToAllBanner(
                                type: .reps,
                                setCount: totalSets,
                                onApply: onApplyRepsToAll,
                                onDismiss: onDismissRepsBanner
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                    }

                    // Weight input with contextual banner
                    VStack(spacing: 8) {
                        WeightInput(
                            title: "set.weight_label".localized,
                            weight: $editingWeight,
                            increment: 0.25
                        ) { newValue in
                            onUpdate(editingReps, newValue)
                        }

                        if hasMultipleSets && weightChanged && !weightBannerDismissed {
                            ApplyToAllBanner(
                                type: .weight,
                                setCount: totalSets,
                                onApply: onApplyWeightToAll,
                                onDismiss: onDismissWeightBanner
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                    }

                    // Delete Set Button
                    Button(role: .destructive) {
                        showingDeleteSetAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                            Text("set.delete".localized)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isExpanded ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isExpanded ? DesignSystem.Colors.tint.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .alert("set.delete.title".localized, isPresented: $showingDeleteSetAlert) {
            Button("set.delete.confirm".localized, role: .destructive) {
                onDelete()
            }
            Button("action.cancel".localized, role: .cancel) {}
        } message: {
            Text("set.delete.message".localized)
        }
    }
}

