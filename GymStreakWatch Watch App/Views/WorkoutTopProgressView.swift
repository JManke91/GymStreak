//
//  WorkoutTopProgressView.swift
//  GymStreakWatch Watch App
//
//  Top zone of the active-workout set editor. Two decoupled context levels
//  (Watch Final Design handoff, §4):
//    1. Routine level  — "Exercise X / Y" label + a NEUTRAL-GRAY segment bar
//       (one segment per exercise, filled by that exercise's completed sets).
//    2. Exercise level — the current exercise name + a "Set X/Y" counter,
//       sitting directly above the value cards.
//  Green is reserved exclusively for the current set (its counter number and
//  the Complete button's fill) so the top bar never reads as exercise progress.
//

import SwiftUI

struct WorkoutTopProgressView: View {
    let exerciseName: String
    /// Zero-based index of the current exercise within the routine.
    let exerciseIndex: Int
    /// Total number of exercises in the routine.
    let exerciseCount: Int
    /// Zero-based index of the current set within the exercise.
    let setIndex: Int
    /// Total number of sets in the current exercise.
    let setCount: Int
    /// Per-exercise completion keyed by stable slot UUID. Structural edits can
    /// shift positions without making SwiftUI animate one exercise as another.
    let exerciseProgress: [WatchWorkoutProgressSegment]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let metrics = WorkoutScreenMetrics.current
    private let accent = OnyxWatch.Colors.accentGreen

    private var barAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// "Exercise 2 / 5" — uppercase routine-level context label.
    private var exerciseCounter: String {
        String(localized: "Exercise \(exerciseIndex + 1) / \(exerciseCount)")
    }

    private var accessibilitySummary: Text {
        Text(exerciseName)
            + Text(", ")
            + Text("Exercise \(exerciseIndex + 1) of \(exerciseCount)")
            + Text(", ")
            + Text("Set \(setIndex + 1) of \(setCount)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.topZoneSpacing + 3) {
            // Routine level: label + neutral-gray segment bar.
            VStack(alignment: .leading, spacing: metrics.topZoneSpacing) {
                Text(exerciseCounter)
                    .font(.system(size: metrics.topPercentSize, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(OnyxWatch.Colors.textMuted)
                    .lineLimit(1)

                HStack(spacing: 2.5) {
                    ForEach(exerciseProgress) { progress in
                        segment(fraction: progress.fraction)
                    }
                }
                .frame(height: metrics.topSegmentHeight)
                .animation(barAnimation, value: exerciseProgress)
            }

            // Exercise level: name + green-accented set counter.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exerciseName)
                    .font(.system(size: metrics.topNameSize, weight: .bold))
                    .foregroundStyle(OnyxWatch.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                setCounter
                    .font(.system(size: metrics.topPercentSize, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// "Set 1/3" — the current set number in green, the rest muted.
    private var setCounter: Text {
        Text(String(localized: "Set") + " ")
            .foregroundColor(OnyxWatch.Colors.textMuted)
            + Text("\(setIndex + 1)")
            .foregroundColor(accent)
            .fontWeight(.bold)
            + Text("/\(setCount)")
            .foregroundColor(OnyxWatch.Colors.textMuted)
    }

    /// One exercise segment: a dark track with a leading neutral-gray fill sized
    /// to the exercise's set progress (a full exercise reads as a solid pill).
    private func segment(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(OnyxWatch.Colors.segmentTrack)

                if fraction > 0 {
                    Capsule()
                        .fill(OnyxWatch.Colors.segmentFill)
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
                exerciseIndex: 1,
                exerciseCount: 5,
                setIndex: 0,
                setCount: 3,
                exerciseProgress: [1, 0.33, 0, 0, 0].map {
                    WatchWorkoutProgressSegment(id: UUID(), fraction: $0)
                }
            )
            WorkoutTopProgressView(
                exerciseName: "Schrägbankdrücken mit Kurzhanteln",
                exerciseIndex: 2,
                exerciseCount: 3,
                setIndex: 1,
                setCount: 2,
                exerciseProgress: [1, 1, 0.5].map {
                    WatchWorkoutProgressSegment(id: UUID(), fraction: $0)
                }
            )
        }
        .padding(.horizontal, 8)
    }
}
