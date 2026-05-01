//
//  PendingSyncBannerView.swift
//  GymStreak
//

import SwiftUI

/// Banner surfaced on the History tab when the HealthKit reconciler has detected
/// HKWorkout records authored by GymStreak that have no matching SwiftData
/// `WorkoutSession`. This is the user-visible end of the watch-sync safety-net
/// layer (see `docs/watch-sync.md`).
///
/// The banner does not auto-create stub WorkoutSessions because HKWorkout lacks
/// per-set rep/weight detail. It instructs the user to re-open GymStreak on
/// their watch — the watch-side persistent retry queue will redeliver the
/// workout when WatchConnectivity becomes reachable again.
struct PendingSyncBannerView: View {
    let orphans: [HealthKitWorkoutReconciler.OrphanedWorkout]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.applewatch")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)

                if let earliest = orphans.last {
                    Text(earliestText(for: earliest))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("history.pendingSync.help".localized)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.warning.opacity(0.35), lineWidth: 1)
        )
    }

    private var titleText: String {
        let format = "history.pendingSync.title".localized
        return String(format: format, orphans.count)
    }

    private func earliestText(for orphan: HealthKitWorkoutReconciler.OrphanedWorkout) -> String {
        let format = "history.pendingSync.earliest".localized
        return String(format: format, Self.dateFormatter.string(from: orphan.startDate))
    }
}

#Preview {
    PendingSyncBannerView(orphans: [
        HealthKitWorkoutReconciler.OrphanedWorkout(
            id: UUID(),
            startDate: Date().addingTimeInterval(-3600 * 26),
            endDate: Date().addingTimeInterval(-3600 * 25),
            duration: 3600,
            activeEnergyBurnedKilocalories: 285,
            sourceBundleIdentifier: "com.shotat24fps.GymStreak.watchkitapp"
        )
    ])
    .padding()
    .background(DesignSystem.Colors.background)
    .preferredColorScheme(.dark)
}
