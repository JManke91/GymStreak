//
//  PRRecordStrip.swift
//  GymStreak
//
//  Gold banner in the workout history detail spelling out a personal record:
//  the PR set (weight × reps) plus the estimated 1RM it produced and the
//  previous best for context.
//

import SwiftUI

struct PRRecordStrip: View {
    let detail: PersonalRecordService.PRDetail
    @Environment(\.weightUnit) private var weightUnit

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .bold))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "history.detail.pr_record".localized,
                            WeightFormatting.label(detail.weight, in: weightUnit),
                            detail.reps))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(estimateLine)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DesignSystem.Colors.pr)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.pr.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The Epley figure is computed and compared in kilograms — only the two
    /// numbers printed here are converted. Both are estimates, so they take the
    /// seam's whole-unit `estimateLabel` rather than an entered weight's
    /// precision.
    private var estimateLine: String {
        let current = WeightFormatting.estimateLabel(detail.estimatedOneRepMax, in: weightUnit)
        if let previous = detail.previousBest {
            return String(format: "history.detail.pr_e1rm_vs".localized,
                          current,
                          WeightFormatting.estimateLabel(previous, in: weightUnit))
        }
        return String(format: "history.detail.pr_e1rm".localized, current)
    }
}
