//
//  ConditioningRunSummaryView.swift
//  GymStreakWatch Watch App
//
//  After a watch conditioning session: complete or ended, the time, and what
//  happened in Apple Health (ticket 06, docs/fight-conditioning.md).
//

import SwiftUI

struct ConditioningRunSummaryView: View {
    let summary: WatchConditioningRunViewModel.Summary
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: OnyxWatch.Spacing.md) {
                Image(systemName: summary.isComplete ? "checkmark.circle.fill" : "flag.checkered")
                    .font(.system(size: 32))
                    .foregroundStyle(OnyxWatch.Colors.tint)
                Text(summary.isComplete ? "Session complete" : "Session ended")
                    .font(.watchHeader)
                Text(WatchConditioningCopy.clock(summary.elapsed))
                    .font(.watchNumberLarge)
                Text(healthLine)
                    .font(.watchCaption)
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Done", action: onDone)
            }
            .padding(.horizontal, OnyxWatch.Spacing.md)
        }
    }

    private var healthLine: LocalizedStringKey {
        switch summary.health {
        case .saved: "Saved to Apple Health"
        case .failed: "Couldn't save to Apple Health"
        case .notSaved: "Nothing saved — the first effort had not started"
        }
    }
}
