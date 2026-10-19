//
//  RoundTimerLiveActivity.swift
//  GymStreakWidgets
//
//  The round timer on the Lock Screen and in the Dynamic Island
//  (docs/fight-conditioning.md, "Round timer" → Live Activity). Two levels:
//  the whole run — a self-advancing countdown to the last bell and a progress
//  bar, which the system keeps right without the app — and the current phase,
//  trusted only until its end: the app updates it at every boundary while on
//  screen and sets `staleDate` to the phase end, so once `isStale` the phase
//  detail gives way to the whole-run level and a quiet "open for the rounds"
//  note. Never a wrong phase. Every string arrives localized from the app.
//
//  On Apple Watch (watchOS 11+) the compact leading / trailing views are what
//  the Smart Stack mirrors, so they carry the phase and its countdown.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RoundTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundTimerAttributes.self) { context in
            RoundTimerLockScreenView(display: RoundTimerDisplay(context))
        } dynamicIsland: { context in
            let display = RoundTimerDisplay(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(display.title, systemImage: RoundTimerDisplay.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(display.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let message = display.completionMessage {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RoundTimerDisplay.accent)
                                .multilineTextAlignment(.trailing)
                        } else if let phase = display.phase {
                            RoundTimerPhasePill(phase: phase)
                            RoundTimerClock(range: phase.range, pauseDate: display.pauseDate, countsDown: true)
                                .font(.title2.bold())
                        } else {
                            Text(display.timeLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            RoundTimerClock(range: display.runRange, pauseDate: display.pauseDate, countsDown: !display.isOpenEnded)
                                .font(.title2.bold())
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if display.completionMessage == nil {
                        RoundTimerRunLine(display: display)
                    }
                }
            } compactLeading: {
                if let phase = display.phase, display.completionMessage == nil {
                    RoundTimerPhasePill(phase: phase)
                } else {
                    Image(systemName: display.completionMessage == nil ? RoundTimerDisplay.symbol : "checkmark.circle.fill")
                        .foregroundStyle(RoundTimerDisplay.accent)
                }
            } compactTrailing: {
                if display.completionMessage == nil {
                    RoundTimerClock(
                        range: display.phase?.range ?? display.runRange,
                        pauseDate: display.pauseDate,
                        countsDown: display.phase != nil || !display.isOpenEnded
                    )
                    .font(.caption2)
                    // Timer text is horizontally flexible in a widget — bound it.
                    .frame(width: 44)
                }
            } minimal: {
                Image(systemName: RoundTimerDisplay.symbol)
                    .foregroundStyle(RoundTimerDisplay.accent)
            }
        }
    }
}

// MARK: - What the views read

/// The activity's content, resolved for rendering: the phase detail only
/// while it is fresh, the completion state when the run is over.
struct RoundTimerDisplay {
    struct Phase {
        let label: String
        let isRound: Bool
        let position: String?
        let range: ClosedRange<Date>
    }

    static let symbol = "bell.fill"
    /// `DesignSystem.Colors.tint` by value — the widget target has no DesignSystem
    /// copy — so the Lock Screen pill matches the runner's. Text on it is black,
    /// the app's contrast rule for the tint.
    static let accent = Color(red: 0 / 255, green: 255 / 255, blue: 133 / 255)

    let title: String
    let subtitle: String
    let isOpenEnded: Bool
    let timeLabel: String
    let pausedLabel: String
    let staleNote: String
    let runRange: ClosedRange<Date>
    let pauseDate: Date?
    let phase: Phase?
    /// True when the app could not update at the phase end: the phase is hidden.
    let isStale: Bool
    let completionMessage: String?

    init(_ context: ActivityViewContext<RoundTimerAttributes>) {
        let attributes = context.attributes
        let state = context.state
        title = attributes.title
        subtitle = attributes.subtitle
        isOpenEnded = attributes.isOpenEnded
        timeLabel = attributes.timeLabel
        pausedLabel = attributes.pausedLabel
        staleNote = attributes.staleNote
        runRange = state.runRange
        pauseDate = state.pauseDate
        isStale = context.isStale
        completionMessage = state.completionMessage
        if !context.isStale, let label = state.phaseLabel, let range = state.phaseRange {
            phase = Phase(label: label, isRound: state.phaseIsRound, position: state.phasePosition, range: range)
        } else {
            phase = nil
        }
    }

    var isPaused: Bool { pauseDate != nil }

    /// The whole-run bar while paused: the system's timer bar cannot pause, so
    /// a fixed value stands in until the next update.
    var pausedRunProgress: Double {
        guard let pauseDate else { return 0 }
        let total = runRange.upperBound.timeIntervalSince(runRange.lowerBound)
        guard total > 0 else { return 0 }
        return max(0, min(1, pauseDate.timeIntervalSince(runRange.lowerBound) / total))
    }
}

// MARK: - Shared pieces

/// A timer the system advances on its own. While paused it is a plain string
/// of the value at the pause: `Text(timerInterval:pauseTime:)` with a pause
/// date already in the past is undocumented and rendered inconsistently
/// across presentations on the simulator (docs/fight-conditioning.md,
/// "Live Activity" → verification), and the next update replaces it anyway.
struct RoundTimerClock: View {
    let range: ClosedRange<Date>
    let pauseDate: Date?
    let countsDown: Bool

    var body: some View {
        Group {
            if let pauseDate {
                Text(Self.clock(countsDown
                                ? range.upperBound.timeIntervalSince(pauseDate)
                                : pauseDate.timeIntervalSince(range.lowerBound)))
            } else {
                Text(timerInterval: range, countsDown: countsDown)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }

    /// "m:ss", or "h:mm:ss" from an hour — `ConditioningCopy.clock` by value.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// ROUND on the accent, REST on the quiet capsule — the runner's pill.
struct RoundTimerPhasePill: View {
    let phase: RoundTimerDisplay.Phase

    var body: some View {
        Text(phase.label)
            .font(.caption2.weight(.heavy))
            .kerning(0.6)
            .foregroundStyle(phase.isRound ? Color.black : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(phase.isRound ? RoundTimerDisplay.accent : Color.secondary.opacity(0.3)))
    }
}

/// The whole-run level: position or stale note, the bar, the time to the last bell.
struct RoundTimerRunLine: View {
    let display: RoundTimerDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if display.isPaused {
                    Text(display.pausedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if let position = display.phase?.position {
                    Text(position)
                        .font(.caption.weight(.semibold))
                } else if display.isStale {
                    Text(display.staleNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if display.phase != nil || display.isStale {
                    Text(display.timeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundTimerClock(range: display.runRange, pauseDate: display.pauseDate, countsDown: !display.isOpenEnded)
                        .font(.subheadline.weight(.semibold))
                        // Timer text is horizontally flexible in a widget; squeezed
                        // below its width it drops digits ("1:--").
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
            if !display.isOpenEnded {
                if display.isPaused {
                    ProgressView(value: display.pausedRunProgress)
                        .tint(RoundTimerDisplay.accent)
                } else {
                    ProgressView(timerInterval: display.runRange, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(RoundTimerDisplay.accent)
                }
            }
        }
    }
}
