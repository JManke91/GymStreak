//
//  SettingsRootView.swift
//  GymStreak
//
//  Root screen of the Settings tab — grouped-inset sections built from
//  `SettingsSectionView` / `SettingsRowView`. See docs/settings-tab.md.
//

import SwiftUI
import UIKit

/// Stack destinations of the Settings tab.
private enum SettingsDestination: Hashable {
    case aiCoach
}

/// Settings tab root: screen title followed by grouped sections.
///
/// Adding a setting means adding a `SettingsSectionView`/`SettingsRowView` pair
/// plus a destination case — the layout code below stays untouched.
struct SettingsRootView: View {

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openURL) private var openURL

    /// Shown when no app accepted the `mailto:` URL — the default state on a
    /// simulator, and real for users who removed every mail client.
    @State private var isShowingMailFallback = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("settings.title".localized)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .kerning(-0.7)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 18)

                        SettingsSectionView(
                            header: "settings.section.data".localized,
                            footer: "settings.section.data.footer".localized
                        ) {
                            ICloudSyncRowView(provider: dependencies.cloudSyncStatus)
                        }

                        SettingsSectionView(
                            header: "settings.section.ai_coach".localized,
                            footer: "settings.section.ai_coach.footer".localized
                        ) {
                            NavigationLink(value: SettingsDestination.aiCoach) {
                                SettingsRowView(
                                    icon: "sparkles",
                                    iconTint: AICoachTheme.accent,
                                    title: "settings.ai_coach.row.title".localized,
                                    subtitle: "settings.ai_coach.row.subtitle".localized,
                                    showsChevron: true,
                                    isLast: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-row-ai-coach")
                        }

                        SettingsSectionView(
                            header: "settings.section.support".localized,
                            footer: "settings.section.support.footer".localized
                        ) {
                            SettingsActionRowView(
                                icon: "star.bubble",
                                title: "settings.support.rate.row.title".localized,
                                subtitle: "settings.support.rate.row.subtitle".localized,
                                action: openAppStoreReview
                            )
                            .accessibilityIdentifier("settings-row-rate-app")

                            SettingsActionRowView(
                                icon: "envelope",
                                title: "settings.support.contact.row.title".localized,
                                subtitle: "settings.support.contact.row.subtitle".localized,
                                isLast: true,
                                action: contactSupport
                            )
                            .accessibilityIdentifier("settings-row-contact-support")
                        }

                        #if DEBUG
                        DebugProEntitlementSectionView(
                            entitlements: dependencies.proEntitlementDebug
                        )

                        DebugProStoreSectionView(
                            entitlements: dependencies.proEntitlementDebug
                        )
                        #endif

                        // Clears the floating tab bar and coach accessory.
                        Color.clear.frame(height: 100)
                    }
                }
            }
            // Keep the tab root free of navigation chrome without passing that
            // preference to its pushed destinations.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .aiCoach:
                    AICoachSettingsView()
                }
            }
            .alert(
                "settings.support.contact.fallback.title".localized,
                isPresented: $isShowingMailFallback
            ) {
                Button("settings.support.contact.fallback.copy".localized) {
                    UIPasteboard.general.string = SupportLinks.supportEmail
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text(
                    String(
                        format: "settings.support.contact.fallback.message".localized,
                        SupportLinks.supportEmail
                    )
                )
            }
        }
    }

    /// Opens the App Store's write-a-review composer for Gym Streak.
    private func openAppStoreReview() {
        guard let url = SupportLinks.writeReview else { return }
        openURL(url)
    }

    /// Hands a prefilled support mail to the user's default mail app.
    ///
    /// Nothing is transmitted by the app — the user reviews and sends the mail.
    /// `accepted` only reports that *some* app opened the URL; it never means a
    /// mail was sent. When no app took it, the address is surfaced in an alert
    /// so the row is never a dead tap.
    private func contactSupport() {
        guard let url = SupportMailComposer.mailtoURL(
            recipient: SupportLinks.supportEmail,
            subject: "settings.support.contact.mail.subject".localized,
            intro: "settings.support.contact.mail.intro".localized,
            diagnostics: dependencies.deviceDiagnostics.current
        ) else {
            isShowingMailFallback = true
            return
        }
        openURL(url) { accepted in
            if !accepted { isShowingMailFallback = true }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsRootView()
        .preferredColorScheme(.dark)
}
