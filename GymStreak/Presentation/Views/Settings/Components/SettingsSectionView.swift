//
//  SettingsSectionView.swift
//  GymStreak
//
//  Grouped-inset section of the Settings tab (design reference
//  `gs-einstellungen.jsx`, SSection). See docs/settings-tab.md.
//

import SwiftUI

/// A settings section: uppercase header, rounded card holding the rows, and an
/// optional explanatory footnote below the card.
///
/// Header and footer are optional — a section may be a bare card (e.g. a single
/// action row) or a card with only a footnote.
struct SettingsSectionView<Content: View>: View {

    let header: String?
    let footer: String?
    @ViewBuilder let content: Content

    init(
        header: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.leading, 6)
                    .padding(.bottom, 8)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color.white.opacity(0.035))
            // The border sits above the rows, so it must stay out of hit testing —
            // otherwise it swallows taps meant for the row underneath.
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 9)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
    }
}

// MARK: - Preview

#Preview("Section") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        SettingsSectionView(
            header: "Data",
            footer: "Your training data syncs automatically across all your devices."
        ) {
            SettingsRowView(
                icon: "icloud",
                iconTint: DesignSystem.Colors.info,
                title: "iCloud",
                subtitle: "Last: today, 14:32",
                showsChevron: true,
                isLast: true
            )
        }
    }
    .preferredColorScheme(.dark)
}
