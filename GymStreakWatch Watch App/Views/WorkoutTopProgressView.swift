//
//  WorkoutTopProgressView.swift
//  GymStreakWatch Watch App
//
//  Top zone of the active-workout set editor: current exercise name, overall
//  workout-completion percent, and a per-exercise segment bar (one segment per
//  exercise, filled by that exercise's completed sets). Design §4 of the
//  Watch Final Design handoff (SwiftUI Handoff.md).
//

import SwiftUI

struct WorkoutTopProgressView: View {
    let exerciseName: String
    /// Whole-workout completion, 0…1 (completed sets / total sets).
    let workoutProgress: Double
    /// Per-exercise completion keyed by stable slot UUID. Structural edits can
    /// shift positions without making SwiftUI animate one exercise as another.
    let exerciseProgress: [WatchWorkoutProgressSegment]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let metrics = WorkoutScreenMetrics.current
    private let accent = OnyxWatch.Colors.accentGreen

    private var percent: Int {
        Int((workoutProgress * 100).rounded())
    }

    private var barAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(spacing: metrics.topZoneSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exerciseName)
                    .font(.system(size: metrics.topNameSize, weight: .bold))
                    .foregroundStyle(OnyxWatch.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                Text("\(percent) %")
                    .font(.system(size: metrics.topPercentSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(percent) percent complete")
            }

            HStack(spacing: 2.5) {
                ForEach(exerciseProgress) { progress in
                    segment(fraction: progress.fraction)
                }
            }
            .frame(height: metrics.topSegmentHeight)
            .animation(barAnimation, value: exerciseProgress)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exerciseName)
    }

    /// One exercise segment: a dark track with a leading green fill sized to the
    /// exercise's set progress (a full exercise reads as a solid green pill).
    private func segment(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(OnyxWatch.Colors.segmentTrack)

                if fraction > 0 {
                    Capsule()
                        .fill(accent)
                        .frame(
                            width: max(
                                metrics.topSegmentHeight,
                                geo.size.width * min(1, fraction)
                            )
                        )
                }
            }
        }
    }
}

#Preview("Top progress") {
    ZStack {
        OnyxWatch.Colors.background.ignoresSafeArea()
        VStack(spacing: 24) {
            WorkoutTopProgressView(
                exerciseName: "Bankdrücken",
                workoutProgress: 0.37,
                exerciseProgress: [1, 0.33, 0, 0, 0].map {
                    WatchWorkoutProgressSegment(id: UUID(), fraction: $0)
                }
            )
            WorkoutTopProgressView(
                exerciseName: "Schrägbankdrücken mit Kurzhanteln",
                workoutProgress: 0.8,
                exerciseProgress: [1, 1, 0.5].map {
                    WatchWorkoutProgressSegment(id: UUID(), fraction: $0)
                }
            )
        }
        .padding(.horizontal, 8)
    }
}
