//
//  ICloudSyncRowView.swift
//  GymStreak
//
//  The iCloud row of the Settings "Data" section: state-tinted icon tile,
//  last-sync timestamp and a status dot/spinner. Design reference
//  `gs-einstellungen.jsx` (SYNC_STATES / SStatusValue). See docs/settings-tab.md.
//

import SwiftUI

/// Settings row that mirrors the live iCloud sync status.
///
/// Subscribes to `CloudSyncStatusProviding` for the lifetime of the row — no
/// polling and no timer, and the subscription is scoped to this row so a status
/// change never re-renders the whole settings root.
struct ICloudSyncRowView: View {

    let provider: any CloudSyncStatusProviding

    /// `nil` until the first value arrives from the stream; the provider's
    /// current status stands in, so the row never renders a wrong state.
    @State private var observedStatus: CloudSyncStatus?

    /// Hoisted out of `body` — allocating a `DateFormatter` per render is the
    /// mistake documented in docs/history-performance.md.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private var status: CloudSyncStatus {
        observedStatus ?? provider.currentStatus
    }

    var body: some View {
        SettingsRowView(
            icon: icon,
            iconTint: tint,
            title: "settings.icloud.row.title".localized,
            subtitle: subtitle,
            isLast: true
        ) {
            statusValue
        }
        .task {
            for await update in provider.statusUpdates() {
                observedStatus = update
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-row-icloud")
    }

    // MARK: - Status element

    @ViewBuilder
    private var statusValue: some View {
        HStack(spacing: 6) {
            if status.state == .syncing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
            }

            Text(statusLabel)
                .font(.system(size: 13.5, weight: .semibold))
                .kerning(-0.2)
                .foregroundStyle(tint)
        }
        .fixedSize()
    }

    // MARK: - State mapping

    private var icon: String {
        switch status.state {
        case .upToDate: "checkmark.icloud"
        case .syncing: "icloud"
        case .waiting: "icloud.slash"
        case .off: "exclamationmark.triangle"
        }
    }

    /// Tone colours of the design reference (`toneColor`): accent green, blue,
    /// amber, red.
    private var tint: Color {
        switch status.state {
        case .upToDate: DesignSystem.Colors.tint
        case .syncing: Color(red: 90/255, green: 180/255, blue: 255/255)
        case .waiting: Color(red: 255/255, green: 197/255, blue: 61/255)
        case .off: Color(red: 255/255, green: 107/255, blue: 107/255)
        }
    }

    private var statusLabel: String {
        switch status.state {
        case .upToDate: "settings.icloud.status.up_to_date".localized
        case .syncing: "settings.icloud.status.syncing".localized
        case .waiting: "settings.icloud.status.waiting".localized
        case .off: "settings.icloud.status.off".localized
        }
    }

    private var subtitle: String {
        if status.state == .off {
            return "settings.icloud.row.subtitle.off".localized
        }
        guard let date = status.lastSuccessfulSync else {
            return "settings.icloud.row.subtitle.never".localized
        }
        return "settings.icloud.row.subtitle.last".localized(
            Self.timestampFormatter.string(from: date)
        )
    }
}

// MARK: - Preview

#Preview("Sync states") {
    /// Static stand-in so the preview can show every state without CloudKit.
    @MainActor
    final class PreviewProvider: CloudSyncStatusProviding {
        let currentStatus: CloudSyncStatus
        init(_ status: CloudSyncStatus) { currentStatus = status }
        func statusUpdates() -> AsyncStream<CloudSyncStatus> {
            AsyncStream { $0.finish() }
        }
    }

    let states: [CloudSyncState] = [.upToDate, .syncing, .waiting, .off]

    return ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        SettingsSectionView(
            header: "settings.section.data".localized,
            footer: "settings.section.data.footer".localized
        ) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                ICloudSyncRowView(
                    provider: PreviewProvider(
                        CloudSyncStatus(state: state, lastSuccessfulSync: .now)
                    )
                )
            }
        }
    }
    .preferredColorScheme(.dark)
}
