//
//  HistoryRings.swift
//  GymStreak
//

import SwiftUI

/// Intensity ring used on the right side of each workout card (RPE-style display).
/// Displays a progress ring (0-100%) with the numeric value and a "RPE" label underneath.
struct IntensityRing: View {
    let value: Int
    var size: CGFloat = 40
    var stroke: CGFloat = 3.5
    var color: Color = DesignSystem.Colors.tint

    var body: some View {
        let clamped = min(100, max(0, value))
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: CGFloat(clamped) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(clamped)")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            }
            .frame(width: size, height: size)

            Text("history.rpe".localized.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

/// Small activity ring used in the WeekHero (behind the flame icon).
struct MiniActivityRing: View {
    let percent: Double      // 0.0 ... 1.0+
    var size: CGFloat = 52
    var stroke: CGFloat = 5
    var color: Color = DesignSystem.Colors.tint

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0, percent))))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

#Preview("Rings") {
    VStack(spacing: 24) {
        IntensityRing(value: 82)
        MiniActivityRing(percent: 0.5)
    }
    .padding()
    .background(DesignSystem.Colors.background)
    .preferredColorScheme(.dark)
}
