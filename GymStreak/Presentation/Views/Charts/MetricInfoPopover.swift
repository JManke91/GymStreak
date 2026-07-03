//
//  MetricInfoPopover.swift
//  GymStreak
//

import SwiftUI

struct MetricInfoPopover: View {
    let metric: ProgressMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.localizedTitle)
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(metric.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: 300)
    }
}
