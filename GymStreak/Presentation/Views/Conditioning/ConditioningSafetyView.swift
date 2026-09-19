//
//  ConditioningSafetyView.swift
//  GymStreak
//
//  The conditioning safety screen, content per docs/fight-conditioning.md
//  ("Safety content the app must show", ACSM pre-participation). Shown once
//  before the first session (with an acknowledgement) and on demand from the
//  library (read-only).
//

import SwiftUI

struct ConditioningSafetyView: View {
    /// `nil` presents the screen read-only, with a close button instead.
    let onAcknowledge: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private static let points: [(symbol: String, key: String)] = [
        ("stethoscope", "conditioning.safety.physician"),
        ("exclamationmark.triangle.fill", "conditioning.safety.stop"),
        ("figure.run", "conditioning.safety.beginner"),
        ("flame", "conditioning.safety.warmup"),
        ("gauge.with.dots.needle.33percent", "conditioning.safety.rpe"),
        ("drop", "conditioning.safety.weight_cut")
    ]

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Text("conditioning.safety.title".localized)
                        .font(.onyxTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("conditioning.safety.intro".localized)
                        .font(.onyxBody)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    ForEach(Self.points, id: \.key) { point in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                            Image(systemName: point.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DesignSystem.Colors.tint)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(point.key.localized)
                                .font(.onyxBody)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                if let onAcknowledge {
                    Button {
                        HapticManager.shared.medium()
                        onAcknowledge()
                    } label: {
                        Text("conditioning.safety.acknowledge".localized)
                            .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
                    }
                    .buttonStyle(.onyxProminent)

                    Button("action.cancel".localized) { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("action.close".localized)
                            .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
                    }
                    .buttonStyle(.onyxProminent)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
    }
}
