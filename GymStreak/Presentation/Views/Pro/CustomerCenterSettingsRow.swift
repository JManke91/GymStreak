//
//  CustomerCenterSettingsRow.swift
//  GymStreak
//
//  The Settings row that opens RevenueCat's Customer Center — restore, manage,
//  cancel, refund. See docs/pro-subscription.md §5j.
//

import SwiftUI
import RevenueCatUI

/// A Settings row that presents `CustomerCenterView`.
///
/// Four things App Review expects to exist — restore purchases (Guideline
/// 3.1.1), manage subscription, cancellation with its survey, and refund
/// requests — arrive as one screen the dashboard configures. None of them is
/// worth hand-building, and the hand-built versions would be four screens to
/// keep correct.
///
/// It lives in `Views/Pro/` rather than beside the Settings components because
/// that is the folder the `RevenueCatUI` import is confined to (§9.2); the
/// subscription section composes it like any other row.
///
/// Every event handler is wired, at minimum to a log line. `CustomerCenterView`
/// is a screen this app does not draw and cannot inspect, so without the log a
/// support question about a restore or a cancellation has no evidence behind it.
struct CustomerCenterSettingsRow: View {

    /// The app's entitlement truth source. Held so a restore completed *inside*
    /// the Customer Center repaints Settings and every gate at once, rather than
    /// waiting on `customerInfoStream` delivery — a restore is precisely the
    /// moment a user is watching for the app to admit they already paid.
    let entitlements: any ProEntitlementProviding

    /// Suppresses the row's bottom separator, like every other Settings row.
    var isLast: Bool = true

    @State private var isPresentingCustomerCenter = false

    var body: some View {
        SettingsActionRowView(
            icon: "person.crop.circle.badge.questionmark",
            iconTint: DesignSystem.Colors.textSecondary,
            title: "settings.subscription.manage.title".localized,
            subtitle: "settings.subscription.manage.subtitle".localized,
            isLast: isLast
        ) {
            isPresentingCustomerCenter = true
        }
        .accessibilityIdentifier("settings-row-customer-center")
        // The handler-taking overload, rather than `CustomerCenterView()` in a
        // sheet of our own: presentation mode, navigation and dismissal are the
        // SDK's business, and the handlers arrive on the same call.
        .presentCustomerCenter(
            isPresented: $isPresentingCustomerCenter,
            restoreStarted: {
                CustomerCenterEvent.restoreStarted.log()
            },
            restoreCompleted: { _ in
                CustomerCenterEvent.restoreCompleted.log()
                // The handed-in `CustomerInfo` is deliberately ignored — judging
                // it here would be a second answer to "is this user Pro", and a
                // laxer one than the gateway's (§3b). Re-resolving through the
                // provider keeps the single rule and repaints everything.
                Task { await entitlements.refresh() }
            },
            restoreFailed: { error in
                CustomerCenterEvent.restoreFailed(error.localizedDescription).log()
            },
            showingManageSubscriptions: {
                CustomerCenterEvent.showingManageSubscriptions.log()
            },
            refundRequestStarted: { productID in
                CustomerCenterEvent.refundRequestStarted(productID: productID).log()
            },
            refundRequestCompleted: { productID, status in
                CustomerCenterEvent.refundRequestCompleted(
                    productID: productID,
                    status: String(describing: status)
                ).log()
            },
            feedbackSurveyCompleted: { optionID in
                CustomerCenterEvent.feedbackSurveyCompleted(optionID: optionID).log()
            },
            managementOptionSelected: { option in
                // `CustomerCenterActionable` is a marker protocol whose
                // conformers are empty structs (`Cancel`, `MissingPurchase`,
                // `RefundRequest`, …), so the type name *is* the event.
                CustomerCenterEvent.managementOptionSelected(
                    String(describing: type(of: option))
                ).log()
            },
            onDismiss: {
                isPresentingCustomerCenter = false
            }
        )
    }
}
