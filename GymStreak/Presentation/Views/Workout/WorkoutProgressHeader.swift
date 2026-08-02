//
//  WorkoutProgressHeader.swift
//  GymStreak
//
//  Sticky header of the active workout: routine, elapsed time, and progress
//  expressed as one segment per set grouped by exercise. A bare "4/22" says how
//  much is left but not where you are — the segments show both, and which
//  exercise the remaining work sits in.
//

import SwiftUI

struct WorkoutProgressHeader: View {
    let routineName: String
    let elapsedTime: TimeInterval
    let completedSets: Int
    let totalSets: Int
    /// Completion flags per set, grouped per exercise, in workout order.
    let segments: [[Bool]]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routineName)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("workout.sets_progress".localized(completedSets, totalSets))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.42))
                }

                Spacer(minLength: 0)

                HStack(spacing: 7) {
                    Circle()
                        .fill(DesignSystem.Colors.tint)
                        .frame(width: 6, height: 6)

                    Text(WorkoutValueFormatting.clock(elapsedTime))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("workout.time".localized)
            }

            segmentBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    /// One 4pt bar per set. Rendered as a single flat row so every segment is the
    /// same width regardless of how the sets divide across exercises; the extra
    /// trailing gap on an exercise's last segment is what groups them visually.
    private var segmentBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { groupIndex, group in
                ForEach(Array(group.enumerated()), id: \.offset) { setIndex, isDone in
                    Capsule()
                        .fill(isDone ? DesignSystem.Colors.tint : Color.white.opacity(0.12))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, setIndex == group.count - 1 && groupIndex < segments.count - 1 ? 6 : 0)
                }
            }
        }
        .animation(DesignSystem.Animation.easeOut, value: completedSets)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack(alignment: .top) {
        DesignSystem.Colors.background.ignoresSafeArea()
        WorkoutProgressHeader(
            routineName: "Upper Body A",
            elapsedTime: 1458,
            completedSets: 4,
            totalSets: 11,
            segments: [
                [true, true, true, true, false],
                [false, false, false],
                [false, false, false]
            ]
        )
    }
    .preferredColorScheme(.dark)
}
