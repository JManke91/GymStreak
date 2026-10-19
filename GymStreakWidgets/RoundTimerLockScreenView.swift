//
//  RoundTimerLockScreenView.swift
//  GymStreakWidgets
//
//  The round timer's Lock Screen / banner presentation — see
//  `RoundTimerLiveActivity.swift` for the two content levels it renders.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RoundTimerLockScreenView: View {
    let display: RoundTimerDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: display.completionMessage == nil ? RoundTimerDisplay.symbol : "checkmark.circle.fill")
                    .foregroundStyle(RoundTimerDisplay.accent)
                Text(display.title)
                    .font(.subheadline.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(display.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            if let message = display.completionMessage {
                Text(message)
                    .font(.title3.bold())
                    .foregroundStyle(RoundTimerDisplay.accent)
            } else if let phase = display.phase {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RoundTimerPhasePill(phase: phase)
                    RoundTimerClock(range: phase.range, pauseDate: display.pauseDate, countsDown: true)
                        .font(.title.bold())
                        .foregroundStyle(display.isPaused ? .secondary : .primary)
                }
                RoundTimerRunLine(display: display)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RoundTimerClock(range: display.runRange, pauseDate: display.pauseDate, countsDown: !display.isOpenEnded)
                        .font(.title.bold())
                        .foregroundStyle(display.isPaused ? .secondary : .primary)
                    Text(display.timeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                RoundTimerRunLine(display: display)
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Round timer", as: .content, using: RoundTimerAttributes(
    title: "Round timer",
    subtitle: "BJJ · 5:00 / 1:00",
    isOpenEnded: false,
    timeLabel: "Time left",
    pausedLabel: "Paused",
    staleNote: "Open Gym Streak for the rounds"
)) {
    RoundTimerLiveActivity()
} contentStates: {
    RoundTimerAttributes.ContentState(
        runRange: Date.now.addingTimeInterval(-7 * 60)...Date.now.addingTimeInterval(28 * 60),
        pauseDate: nil,
        phaseLabel: "ROUND",
        phaseIsRound: true,
        phasePosition: "Round 2 of 6",
        phaseRange: Date.now.addingTimeInterval(-60)...Date.now.addingTimeInterval(4 * 60),
        completionMessage: nil
    )
    RoundTimerAttributes.ContentState(
        runRange: Date.now.addingTimeInterval(-11 * 60)...Date.now.addingTimeInterval(24 * 60),
        pauseDate: Date.now,
        phaseLabel: "REST",
        phaseIsRound: false,
        phasePosition: "Round 2 of 6",
        phaseRange: Date.now.addingTimeInterval(-20)...Date.now.addingTimeInterval(40),
        completionMessage: nil
    )
    RoundTimerAttributes.ContentState(
        runRange: Date.now...Date.now,
        pauseDate: nil,
        phaseLabel: nil,
        phaseIsRound: false,
        phasePosition: nil,
        phaseRange: nil,
        completionMessage: "Rounds complete · 6 rounds · 35:00"
    )
}
