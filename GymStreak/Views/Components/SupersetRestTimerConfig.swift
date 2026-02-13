//
//  SupersetRestTimerConfig.swift
//  GymStreak
//
//  Created by Claude Code
//

import SwiftUI

/// Rest timer configuration for a superset group.
/// Shows a single rest timer config that applies to the entire superset,
/// with explanatory text about when the rest timer triggers.
struct SupersetRestTimerConfig: View {
    @Binding var restTime: TimeInterval
    @Binding var isExpanded: Bool
    var onRestTimeChange: ((TimeInterval) -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            RestTimerConfigView(
                restTime: $restTime,
                isExpanded: $isExpanded,
                showToggle: true,
                onRestTimeChange: onRestTimeChange
            )

            // Explanatory text when expanded
            if isExpanded && restTime > 0 {
                Text("superset.rest_timer.explanation".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Collapsed
        SupersetRestTimerConfig(
            restTime: .constant(90),
            isExpanded: .constant(false)
        )

        // Expanded
        SupersetRestTimerConfig(
            restTime: .constant(90),
            isExpanded: .constant(true)
        )

        // Disabled
        SupersetRestTimerConfig(
            restTime: .constant(0),
            isExpanded: .constant(false)
        )
    }
    .padding()
}
