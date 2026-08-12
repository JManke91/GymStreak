//
//  SettingsRootView.swift
//  GymStreak
//
//  Root screen of the Settings tab — grouped-inset sections built from
//  `SettingsSectionView` / `SettingsRowView`. See docs/settings-tab.md.
//

import SwiftUI

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
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsRootView()
        .preferredColorScheme(.dark)
}
