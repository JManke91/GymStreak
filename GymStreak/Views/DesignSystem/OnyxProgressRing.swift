//
//  OnyxProgressRing.swift
//  GymStreak
//
//  Circular progress indicator for the Onyx Design System
//

import SwiftUI

/// A circular progress indicator styled with Onyx Design System
struct OnyxProgressRing: View {
    let progress: Double // 0.0 to 1.0
    let lineWidth: CGFloat
    let size: CGFloat
    let showPercentage: Bool
    let color: Color

    init(
        progress: Double,
        lineWidth: CGFloat = 12,
        size: CGFloat = 160,
        showPercentage: Bool = true,
        color: Color = DesignSystem.Colors.tint
    ) {
        self.progress = min(max(progress, 0), 1) // Clamp to 0-1
        self.lineWidth = lineWidth
        self.size = size
        self.showPercentage = showPercentage
        self.color = color
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(DesignSystem.Colors.divider, lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            // Center content
            if showPercentage {
                VStack(spacing: 4) {
                    Text("\(Int(progress * 100))%")
                        .font(.onyxNumberLarge)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
            }
        }
    }
}

/// A compact progress ring for inline use
struct OnyxCompactProgressRing: View {
    let progress: Double
    let color: Color
    let size: CGFloat

    init(
        progress: Double,
        color: Color = DesignSystem.Colors.tint,
        size: CGFloat = 32
    ) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.Colors.divider, lineWidth: 3)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

// MARK: - Previews

#Preview("Progress Rings") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 32) {
            OnyxProgressRing(progress: 0.75)

            HStack(spacing: 24) {
                OnyxProgressRing(progress: 0.25, size: 80, showPercentage: false)
                OnyxProgressRing(progress: 0.5, size: 80, showPercentage: false, color: DesignSystem.Colors.success)
                OnyxProgressRing(progress: 1.0, size: 80, showPercentage: false, color: DesignSystem.Colors.warning)
            }

            HStack(spacing: 16) {
                OnyxCompactProgressRing(progress: 0.3)
                OnyxCompactProgressRing(progress: 0.6, color: DesignSystem.Colors.success)
                OnyxCompactProgressRing(progress: 0.9, color: DesignSystem.Colors.warning)
            }
        }
        .padding()
    }
}
