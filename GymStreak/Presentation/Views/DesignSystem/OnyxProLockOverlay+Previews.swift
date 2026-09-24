//
//  OnyxProLockOverlay+Previews.swift
//  GymStreak
//
//  Previews for the §8 C blurred-preview lock, split out so the component file
//  stays inside the size convention. The two content structs stand in for the
//  two shapes the lock has to serve: a short card (the conditioning weekly
//  targets, which the first version overflowed) and a tall one (a chart).
//

import SwiftUI

// MARK: - Previews

private struct ProLockShortContent: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ForEach(["Lactic 30/120", "Aerobic base"], id: \.self) { title in
                HStack(spacing: DesignSystem.Spacing.md) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignSystem.Colors.tint)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text("2 rounds")
                            .font(.onyxCaption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("0 of 2")
                        .font(.onyxCaption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .padding(DesignSystem.Dimensions.cardPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
                .fill(DesignSystem.Colors.card)
        )
    }
}

private struct ProLockTallContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Estimated 1RM")
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("142.5 kg")
                .font(.onyxNumberLarge)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach([0.4, 0.55, 0.5, 0.7, 0.65, 0.85, 1.0], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignSystem.Colors.tint)
                        .frame(height: 140 * height)
                }
            }
            .frame(height: 140)
        }
        .padding(DesignSystem.Dimensions.cardPadding)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Short content — the case that used to overflow") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockShortContent()
            .proLocked(
                true,
                placement: .conditioningProgram,
                subtitle: "Your weeks 5–12 are planned and waiting.",
                footnote: "Every session you logged stays yours, and single sessions stay free."
            ) { }
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Tall content") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockTallContent()
            .proLocked(true, placement: .chartWindow) { }
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Short content — large type") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockShortContent()
            .proLocked(
                true,
                placement: .conditioningProgram,
                footnote: "Every session you logged stays yours."
            ) { }
            .padding()
    }
    .dynamicTypeSize(.accessibility1)
    .preferredColorScheme(.dark)
}

#Preview("Unlocked passthrough") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockShortContent()
            .proLocked(false, placement: .chartMetric) { }
            .padding()
    }
    .preferredColorScheme(.dark)
}
