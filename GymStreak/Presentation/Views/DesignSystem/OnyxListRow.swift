//
//  OnyxListRow.swift
//  GymStreak
//
//  Standard list row with leading/trailing slots for the Onyx Design System
//

import SwiftUI

/// A standard list row styled with Onyx Design System
struct OnyxListRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            leading()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.onyxCaption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.listRowBackground)
    }
}

/// A simple list row with just title and optional subtitle
struct OnyxSimpleListRow: View {
    let title: String
    let subtitle: String?
    let showChevron: Bool

    init(title: String, subtitle: String? = nil, showChevron: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
    }

    var body: some View {
        OnyxListRow(title: title, subtitle: subtitle) {
            // No leading content
        } trailing: {
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Previews

#Preview("List Rows") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 1) {
            OnyxSimpleListRow(title: "Bench Press", subtitle: "3 sets")

            OnyxSimpleListRow(title: "Squats", subtitle: "4 sets")

            OnyxListRow(title: "Deadlift", subtitle: "3 sets") {
                OnyxBadge(text: "LT", color: DesignSystem.Colors.tint)
            } trailing: {
                Text("120 kg")
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }
}
