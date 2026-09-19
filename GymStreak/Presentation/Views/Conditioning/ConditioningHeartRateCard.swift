//
//  ConditioningHeartRateCard.swift
//  GymStreak
//
//  The heart-rate line of a session preview: the personal aerobic target, a
//  prompt to set the profile up, the RPE-only note, or — for alactic power —
//  why there is no heart-rate target. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningHeartRateCard: View {
    let guidance: ConditioningHeartRateGuidance
    let onEdit: () -> Void

    var body: some View {
        if guidance != .none {
            OnyxCard {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    Image(systemName: guidance == .maximalIntent ? "bolt.fill" : "heart.fill")
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text(title)
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        if let detail {
                            Text(detail)
                                .font(.onyxFootnote)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let action {
                            Button(action, action: onEdit)
                                .font(.onyxSubheadline.weight(.semibold))
                                .foregroundStyle(DesignSystem.Colors.tint)
                                .padding(.top, DesignSystem.Spacing.xs)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var title: String {
        switch guidance {
        case .none, .maximalIntent: "conditioning.hr.preview.maximal_title".localized
        case .needsSetup: "conditioning.hr.preview.setup_title".localized
        case .rpeOnly: "conditioning.hr.preview.rpe_title".localized
        case .target(let target):
            "conditioning.hr.preview.target".localized(
                ConditioningCopy.heartRateRange(target), ConditioningCopy.heartRateBasis(target)
            )
        }
    }

    private var detail: String? {
        switch guidance {
        case .none: nil
        case .maximalIntent: "conditioning.hr.preview.maximal_detail".localized
        case .needsSetup: "conditioning.hr.preview.setup_detail".localized
        case .rpeOnly: "conditioning.hr.preview.rpe_detail".localized
        case .target(let target):
            target.isMaxEstimated
                ? "conditioning.hr.preview.estimate_note".localized(HeartRateZones.estimateUncertainty)
                : "conditioning.hr.preview.measured_note".localized
        }
    }

    private var action: String? {
        switch guidance {
        case .none, .maximalIntent: nil
        case .needsSetup: "conditioning.hr.preview.setup_action".localized
        case .rpeOnly, .target: "conditioning.hr.preview.edit_action".localized
        }
    }
}
