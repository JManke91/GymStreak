//
//  GymStreakWidgetsLiveActivity.swift
//  GymStreakWidgets
//
//  Created by Julian Manke on 15.11.25.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct GymStreakWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / Banner UI
            RestTimerLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI - shown when user long-presses
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Rest", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let exercise = context.state.exerciseName {
                            Text(exercise)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let message = context.state.completionMessage {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Text(timerInterval: context.state.timerRange, countsDown: true)
                                .monospacedDigit()
                                .font(.title2.bold())
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // Circular progress indicator
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                                .frame(width: 32, height: 32)

                            Circle()
                                .trim(from: 0, to: progress(for: context))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 32, height: 32)
                                .rotationEffect(.degrees(-90))
                        }

                        Spacer()

                        Text(context.attributes.workoutName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                // Compact view - leading area
                Image(systemName: "timer")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                // Compact view - trailing area
                if let message = context.state.completionMessage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(timerInterval: context.state.timerRange, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                }
            } minimal: {
                // Minimal view - single icon when multiple activities active
                Image(systemName: "timer")
                    .foregroundStyle(.blue)
            }
        }
    }

    // Calculate progress for circular indicator
    private func progress(for context: ActivityViewContext<RestTimerAttributes>) -> Double {
        let now = Date()
        let start = context.state.timerRange.lowerBound
        let end = context.state.timerRange.upperBound
        let total = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        return max(0, min(1, 1 - (elapsed / total)))
    }
}

// MARK: - Lock Screen View

struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                if let _ = context.state.completionMessage {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "timer")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Header with workout name
                HStack(spacing: 4) {
                    Text("Rest Timer")
                        .font(.subheadline.weight(.semibold))

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(context.attributes.workoutName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Countdown timer or completion message
                if let message = context.state.completionMessage {
                    Text(message)
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                } else {
                    Text(timerInterval: context.state.timerRange, countsDown: true)
                        .font(.title.bold())
                        .monospacedDigit()
                }

                // Exercise context
                if let exercise = context.state.exerciseName, context.state.completionMessage == nil {
                    Text(exercise)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding()
    }

    private var progress: Double {
        let now = Date()
        let start = context.state.timerRange.lowerBound
        let end = context.state.timerRange.upperBound
        let total = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        return max(0, min(1, 1 - (elapsed / total)))
    }
}

// MARK: - Previews

#Preview("Notification", as: .content, using: RestTimerAttributes(workoutName: "Push Day")) {
    GymStreakWidgetsLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        timerRange: Date.now...Date.now.addingTimeInterval(90),
        exerciseName: "Bench Press"
    )
    RestTimerAttributes.ContentState(
        timerRange: Date.now...Date.now.addingTimeInterval(30),
        exerciseName: "Incline Dumbbell Press"
    )
    RestTimerAttributes.ContentState(
        timerRange: Date.now...Date.now,
        exerciseName: nil,
        completionMessage: "Rest Complete! 💪"
    )
}
