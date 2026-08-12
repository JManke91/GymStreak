//
//  SettingsRowView.swift
//  GymStreak
//
//  Shared row shape of the Settings tab (design reference `gs-einstellungen.jsx`, SRow).
//  Every setting reuses this row — see docs/settings-tab.md.
//

import SwiftUI

/// One row inside a `SettingsSectionView` card.
///
/// Shape: optional tinted icon tile · title with optional subtitle · optional
/// value and/or trailing element · optional chevron. A hairline separator is
/// drawn at the bottom unless `isLast` is set; it insets past the icon tile.
struct SettingsRowView<Trailing: View>: View {

    /// SF Symbol for the leading icon tile. `nil` renders the row without a tile.
    let icon: String?
    /// Tint of the icon tile — fills the glyph, its background and its border.
    let iconTint: Color
    let title: String
    let subtitle: String?
    /// Right-hand value text (e.g. "iPhone, Apple Watch").
    let value: String?
    let showsChevron: Bool
    /// Suppresses the bottom separator for the last row of a card.
    let isLast: Bool
    /// Right-hand element (toggle, status dot, …) shown after `value`.
    let trailing: Trailing

    init(
        icon: String? = nil,
        iconTint: Color = DesignSystem.Colors.tint,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        showsChevron: Bool = false,
        isLast: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.showsChevron = showsChevron
        self.isLast = isLast
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                iconTile(icon)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .kerning(-0.2)
                    .foregroundStyle(Color.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .kerning(-0.1)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let value {
                Text(value)
                    .font(.system(size: 14).monospacedDigit())
                    .kerning(-0.2)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }

            trailing

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.28))
            }
        }
        .padding(.vertical, icon == nil ? 13 : 11)
        .padding(.horizontal, icon == nil ? 16 : 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, icon == nil ? 16 : 60)
                    .allowsHitTesting(false)
            }
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(iconTint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(iconTint.opacity(0.28), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconTint)
            )
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
    }
}

// MARK: - Convenience init

extension SettingsRowView where Trailing == EmptyView {
    init(
        icon: String? = nil,
        iconTint: Color = DesignSystem.Colors.tint,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        showsChevron: Bool = false,
        isLast: Bool = false
    ) {
        self.init(
            icon: icon,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle,
            value: value,
            showsChevron: showsChevron,
            isLast: isLast,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Preview

#Preview("Row variants") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionView(header: "Variants", footer: "Every combination of icon, subtitle, value, trailing element and chevron.") {
                    SettingsRowView(
                        icon: "sparkles",
                        title: "Icon, subtitle, chevron",
                        subtitle: "With subtitle",
                        showsChevron: true
                    )
                    SettingsRowView(title: "Plain title only")
                    SettingsRowView(
                        icon: "icloud",
                        iconTint: DesignSystem.Colors.info,
                        title: "Icon and value",
                        value: "12.4 MB"
                    )
                    SettingsRowView(
                        title: "Trailing element",
                        subtitle: "No icon tile",
                        isLast: true
                    ) {
                        Toggle("", isOn: .constant(true))
                            .labelsHidden()
                            .tint(DesignSystem.Colors.tint)
                    }
                }
            }
        }
    }
    .preferredColorScheme(.dark)
}
