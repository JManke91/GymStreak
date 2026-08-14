//
//  SettingsActionRowView.swift
//  GymStreak
//
//  Tappable counterpart of the navigation rows in the Settings tab: same row
//  shape, but it runs a closure instead of pushing a destination.
//  See docs/settings-tab.md.
//

import SwiftUI

/// A `SettingsRowView` that performs an action on tap.
///
/// Navigation rows wrap `SettingsRowView` in a `NavigationLink(value:)`; rows that
/// *do* something (open a link, present a sheet) wrap it here instead, so the
/// button and press handling live in one place.
struct SettingsActionRowView: View {

    let icon: String?
    let iconTint: Color
    let title: String
    let subtitle: String?
    let showsChevron: Bool
    let isLast: Bool
    let action: () -> Void

    init(
        icon: String? = nil,
        iconTint: Color = DesignSystem.Colors.tint,
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true,
        isLast: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.isLast = isLast
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRowView(
                icon: icon,
                iconTint: iconTint,
                title: title,
                subtitle: subtitle,
                showsChevron: showsChevron,
                isLast: isLast
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Action rows") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ScrollView {
            SettingsSectionView(header: "Support") {
                SettingsActionRowView(
                    icon: "star.bubble",
                    title: "Rate app",
                    subtitle: "Opens the App Store",
                    isLast: true
                ) {}
            }
        }
    }
    .preferredColorScheme(.dark)
}
