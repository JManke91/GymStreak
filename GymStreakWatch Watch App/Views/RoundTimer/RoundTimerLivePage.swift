//
//  RoundTimerLivePage.swift
//  GymStreakWatch Watch App
//
//  The round timer's main page (positioning ticket 07,
//  docs/fight-conditioning.md "Round timer"): round or rest, the countdown,
//  which round, and live heart rate — sized like the mat session's live page,
//  so it fits every watch without scrolling. Value inputs only.
//

import SwiftUI

struct RoundTimerLivePage: View {
    let position: ConditioningPosition
    let reading: ConditioningHeartRateReading
    let isPaused: Bool

    var body: some View {
        let isRound = position.phase.kind == .work
        VStack(spacing: OnyxWatch.Spacing.sm) {
            Text(isRound ? String(localized: "ROUND") : WatchConditioningCopy.phase(position.phase.kind))
                .font(.system(.caption2, design: .rounded).weight(.black))
                .tracking(1)
                .padding(.vertical, 3)
                .padding(.horizontal, 10)
                // The round on the tint with black text — never white on the tint.
                .foregroundStyle(isRound ? OnyxWatch.Colors.textOnTint : OnyxWatch.Colors.textPrimary)
                .background(Capsule().fill(isRound ? OnyxWatch.Colors.tint : OnyxWatch.Colors.cardElevated))
            Text(WatchConditioningCopy.clock(position.remainingInPhase))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(countsDown: true))
            if let round = WatchMatSessionCopy.round(position.phase) {
                Text(round)
                    .font(.system(.footnote, design: .rounded).weight(.heavy))
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: OnyxWatch.Spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(OnyxWatch.Colors.destructive)
                ConditioningHeartRateValue(reading: reading, size: 24, scale: 1)
                if reading.bpm != nil {
                    Text("bpm")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(OnyxWatch.Colors.textSecondary)
                }
            }
            if isPaused {
                Text("Paused")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(OnyxWatch.Colors.warning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
