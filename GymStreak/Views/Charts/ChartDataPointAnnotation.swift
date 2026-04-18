//
//  ChartDataPointAnnotation.swift
//  GymStreak
//

import SwiftUI

struct ChartDataPointAnnotation: View {
    let selectedPoint: SelectedDataPoint

    var body: some View {
        VStack(spacing: 4) {
            Text(selectedPoint.displayValue)
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(selectedPoint.displayDate)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
