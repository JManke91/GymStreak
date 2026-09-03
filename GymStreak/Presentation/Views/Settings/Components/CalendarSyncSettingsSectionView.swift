//
//  CalendarSyncSettingsSectionView.swift
//  GymStreak
//
//  Settings section for the Apple Calendar opt-in. See docs/calendar-sync.md.
//

import SwiftUI
import UIKit

/// One toggle that owns the whole feature: it asks for Calendar access and
/// gives the app its own "GymStreak" calendar, and switching it off takes that
/// calendar — and everything the app ever wrote into it — away again.
///
/// The toggle lives here rather than in the planning sheet because it carries a
/// system permission and applies to every routine at once — the same reasoning
/// that puts Apple Health in Settings.
struct CalendarSyncSettingsSectionView: View {

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CalendarSyncSettingsViewModel

    init(
        preference: any CalendarSyncPreferenceProviding,
        sync: any WorkoutCalendarSyncing,
        mirror: any PlannedWorkoutCalendarMirroring
    ) {
        self._viewModel = State(
            wrappedValue: CalendarSyncSettingsViewModel(
                preference: preference,
                sync: sync,
                mirror: mirror
            )
        )
    }

    var body: some View {
        SettingsSectionView(
            header: "calendar_sync.section.title".localized,
            footer: "calendar_sync.section.footer".localized
        ) {
            toggleRow

            if let failure = viewModel.failure {
                failureRow(failure)
            }
        }
        // Both take-it-away cases happen outside the app and iOS announces
        // neither, so the row checks rather than waits (docs/calendar-sync.md
        // §12). `.onAppear` covers opening Settings; the scene phase covers the
        // trip to Settings.app and back, after which this view is still on
        // screen and `.onAppear` never fires again. Two reads of a cached
        // authorization status — no EventKit query, and no write on either path.
        .onAppear { viewModel.refreshStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { viewModel.refreshStatus() }
        }
    }

    // MARK: - Rows

    private var toggleRow: some View {
        SettingsRowView(
            icon: "calendar",
            title: "calendar_sync.row.title".localized,
            subtitle: "calendar_sync.row.subtitle".localized,
            isLast: viewModel.failure == nil
        ) {
            if viewModel.isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DesignSystem.Colors.tint)
            }

            Toggle("", isOn: toggleBinding)
                .labelsHidden()
                .tint(DesignSystem.Colors.tint)
                .disabled(viewModel.isWorking)
                .accessibilityIdentifier("settings-calendar-sync-toggle")
        }
    }

    /// The denied case is a tappable row: telling the user the permission is
    /// missing without taking them where they can grant it is a dead end.
    @ViewBuilder
    private func failureRow(_ failure: CalendarSyncSettingsViewModel.Failure) -> some View {
        switch failure {
        case .accessDenied:
            SettingsActionRowView(
                icon: "exclamationmark.triangle",
                iconTint: DesignSystem.Colors.warning,
                title: "calendar_sync.denied.title".localized,
                subtitle: "calendar_sync.denied.subtitle".localized,
                isLast: true,
                action: openSystemSettings
            )
            .accessibilityIdentifier("settings-calendar-sync-denied")

        case .noWritableSource, .writeFailed:
            SettingsRowView(
                icon: "exclamationmark.triangle",
                iconTint: DesignSystem.Colors.warning,
                title: "calendar_sync.failed.title".localized,
                subtitle: failure == .noWritableSource
                    ? "calendar_sync.failed.no_source.subtitle".localized
                    : "calendar_sync.failed.write.subtitle".localized,
                isLast: true
            )
            .accessibilityIdentifier("settings-calendar-sync-failed")
        }
    }

    // MARK: - Actions

    /// Reads through the view model so the switch follows the user's finger
    /// while the permission prompt is up, and reverts on its own when the
    /// request is refused.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { newValue in
                Task { await viewModel.setEnabled(newValue) }
            }
        )
    }

    /// Opens this app's page in Settings, where Calendars access is granted.
    /// The URL is a system constant, so the guard is only there because
    /// `URL(string:)` is failable.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - Preview

#Preview("Calendar sync") {
    /// Stand-in that grants immediately — the preview must not touch EventKit.
    @MainActor
    final class PreviewSync: WorkoutCalendarSyncing {
        var accessStatus: CalendarAccessStatus = .fullAccess
        var appCalendarIdentifier: String?
        func enable() async throws { appCalendarIdentifier = "preview" }
        func mirror(_ desired: PlannedWorkoutCalendarState) throws {}
        func disable() throws { appCalendarIdentifier = nil }
    }

    /// The preview writes no events either — it has no repositories to read
    /// plans from and no calendar to write them to.
    @MainActor
    final class PreviewMirror: PlannedWorkoutCalendarMirroring {
        func reconcile(revalidatingCalendar: Bool) {}
    }

    return ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        // A throwaway suite, not `.shared`: a preview must not write the opt-in
        // into the real `UserDefaults`.
        CalendarSyncSettingsSectionView(
            preference: CalendarSyncPreference(
                defaults: UserDefaults(suiteName: "preview.calendar_sync")!
            ),
            sync: PreviewSync(),
            mirror: PreviewMirror()
        )
    }
    .preferredColorScheme(.dark)
}
