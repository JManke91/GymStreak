//
//  ChartTimeframePicker.swift
//  GymStreak
//

import SwiftUI

struct ChartTimeframePicker: View {
    @Binding var selection: ChartTimeframe
    var onSelectionChanged: ((ChartTimeframe) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChartTimeframe.allCases) { timeframe in
                Button {
                    withAnimation(DesignSystem.Animation.snappy) {
                        selection = timeframe
                        onSelectionChanged?(timeframe)
                    }
                } label: {
                    Text(timeframe.localizedTitle)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selection == timeframe
                                ? DesignSystem.Colors.tint
                                : Color.clear
                        )
                        .foregroundStyle(
                            selection == timeframe
                                ? DesignSystem.Colors.textOnTint
                                : DesignSystem.Colors.textSecondary
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selection: ChartTimeframe = .month

        var body: some View {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()
                ChartTimeframePicker(selection: $selection)
                    .padding()
            }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
