//
//  RestorePurchasesSettingsRow.swift
//  GymStreak
//
//  The Settings row a free user restores from. See docs/pro-subscription.md §5i.
//

import SwiftUI

/// A Settings row that runs a restore and says what happened.
///
/// **Why this exists rather than the Customer Center.** Guideline 3.1.1 requires
/// a restore path that does not depend on the app already believing the user
/// paid. Until 1.1.10 that path was `CustomerCenterSettingsRow`, shown to free
/// users as *"Manage subscription — restore, change, cancel or request a
/// refund"*. For someone who has never bought anything, that screen opens on
/// **"No subscriptions found"** — App Review took it twice, could find no way to
/// buy, and attached a screenshot of it to the second rejection
/// (`appstore-rejection-1.1.9.md` §3.7). A free user now gets *Restore
/// purchases*, which does one thing and names it; the Customer Center is shown
/// only to people with something to manage.
///
/// **It reports all three outcomes.** A restore that could not run must not be
/// reported as "you own nothing" — telling someone who paid that they did not is
/// the worst thing this row can do. `ProRestoreOutcome` carries the distinction
/// out of the Data layer so this view only has to look up copy for it.
///
/// No entitlement decision is made here: `restorePurchases()` composes the
/// result through the same provider every gate reads, so a successful restore
/// repaints Settings and all nine gates before the alert is even dismissed.
struct RestorePurchasesSettingsRow: View {

    let entitlements: any ProEntitlementProviding

    /// Suppresses the row's bottom separator, like every other Settings row.
    var isLast: Bool = true

    @State private var isRestoring = false
    @State private var outcome: ProRestoreOutcome?

    var body: some View {
        SettingsActionRowView(
            icon: "arrow.clockwise",
            iconTint: DesignSystem.Colors.textSecondary,
            title: "settings.subscription.restore.title".localized,
            subtitle: isRestoring
                ? "settings.subscription.restore.subtitle.running".localized
                : "settings.subscription.restore.subtitle".localized,
            showsChevron: !isRestoring,
            isLast: isLast
        ) {
            restore()
        }
        .disabled(isRestoring)
        .accessibilityIdentifier("settings-row-restore-purchases")
        // Bound to the outcome rather than to a separate `isPresenting` flag, so
        // there is no window in which the alert is up and the message is stale.
        .alert(
            (outcome?.titleKey ?? "").localized,
            isPresented: Binding(
                get: { outcome != nil },
                set: { if !$0 { outcome = nil } }
            ),
            presenting: outcome
        ) { _ in
            Button("common.ok".localized, role: .cancel) { outcome = nil }
        } message: { outcome in
            Text(outcome.messageKey.localized)
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            let result = await entitlements.restorePurchases()
            isRestoring = false
            outcome = result
        }
    }
}

// MARK: - Copy

private extension ProRestoreOutcome {

    var titleKey: String {
        switch self {
        case .restored: "settings.subscription.restore.restored.title"
        case .nothingFound: "settings.subscription.restore.none.title"
        case .failed: "settings.subscription.restore.failed.title"
        }
    }

    var messageKey: String {
        switch self {
        case .restored: "settings.subscription.restore.restored.message"
        case .nothingFound: "settings.subscription.restore.none.message"
        case .failed: "settings.subscription.restore.failed.message"
        }
    }
}
