import SwiftUI

/// One compact line under the summary header saying whether the workout has
/// reached the iPhone. No background fill, so the summary's primary action
/// keeps its position on the smallest watch.
struct WatchSummarySyncStatusRow: View {
    let status: WatchSummarySyncStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxWatch.Spacing.sm) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(iconColor)
                // A slow spin says the save is in progress, not stuck.
                .symbolEffect(.rotate, options: .repeat(.continuous).speed(0.5), isActive: status == .saving)
            Text(message)
                .font(.watchCaption2)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.25), value: status)
    }

    private var iconName: String {
        switch status {
        case .saving: "arrow.triangle.2.circlepath"
        case .waitingForPhone: "applewatch"
        case .saved: "checkmark.circle.fill"
        case .notSent: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .saving, .waitingForPhone: OnyxWatch.Colors.textSecondary
        case .saved: OnyxWatch.Colors.tint
        case .notSent: OnyxWatch.Colors.warning
        }
    }

    private var textColor: Color {
        status == .saved ? OnyxWatch.Colors.textPrimary : OnyxWatch.Colors.textSecondary
    }

    private var message: LocalizedStringKey {
        switch status {
        case .saving: "Saving to iPhone…"
        case .waitingForPhone: "Safe on this watch — syncs when your iPhone is nearby."
        case .saved: "Saved on iPhone"
        case .notSent: "Couldn't send to iPhone"
        }
    }
}
