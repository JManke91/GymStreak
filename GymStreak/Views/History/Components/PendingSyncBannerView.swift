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
/// The rich per-set payload is gone by the time the banner appears, so tapping the
/// recover button rebuilds each missing `WorkoutSession` from the matched routine
/// template (a best-effort) using the HKWorkout's date/duration and external UUID.
/// This works even when the watch can no longer redeliver (e.g. it already cleared
/// its queue, or the app was reinstalled) — HealthKit is the surviving source.
struct PendingSyncBannerView: View {
    let orphans: [HealthKitWorkoutReconciler.OrphanedWorkout]
    /// Invoked when the user *confirms* recovery in the dialog. The caller runs the
    /// reconstruction. The confirmation dialog is hosted here (on the button) rather
    /// than on the parent container: on iOS 26 a `confirmationDialog` anchors to the
    /// view its modifier is attached to, so attaching it to a large ancestor makes it
    /// mis-anchor as a floating popover. Keeping it on the button anchors it correctly.
    var onRecover: () -> Void = {}

    @State private var showingConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Button {
                showingConfirm = true
            } label: {
                Text("history.pendingSync.recover".localized)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignSystem.Colors.warning)
                    )
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "history.pendingSync.recover.title".localized,
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("history.pendingSync.recover.confirm".localized) {
                    onRecover()
                }
                Button("action.cancel".localized, role: .cancel) {}
            } message: {
                Text("history.pendingSync.recover.message".localized)
            }
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
            sourceBundleIdentifier: "com.shotat24fps.GymStreak.watchkitapp",
            routineName: "Push Day",
            routineId: nil
        )
    ])
    .padding()
    .background(DesignSystem.Colors.background)
    .preferredColorScheme(.dark)
}
