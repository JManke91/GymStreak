//
//  PaywallPlaceholderView.swift
//  GymStreak
//
//  The stand-in paywall: it proves the presentation seam works before a real
//  paywall exists. Ticket 14 replaces this view with a RevenueCat paywall.
//  See docs/pro-subscription.md.
//

import SwiftUI

/// What a raised placement currently looks like.
///
/// It shows the headline the placement carries — §8 C requires a contextual gate
/// to name the thing being unlocked rather than say "Go Pro" — and nothing else:
/// there is no offer here, because there is no purchase surface in a shipping
/// build until ticket 14. In DEBUG it also prints the placement identifier, so
/// the debug section proves *which* placement was raised.
struct PaywallPlaceholderView: View {

    let placement: PaywallPlacement

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.lg) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)

                Text(placement.headlineKey.localized)
                    .font(.onyxTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("paywall.placeholder.body".localized)
                    .font(.onyxBody)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                #if DEBUG
                Text(placement.identifier)
                    .font(.onyxCaption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                #endif

                OnyxButton("action.dismiss".localized, style: .secondary) {
                    dismiss()
                }
                .padding(.top, DesignSystem.Spacing.sm)
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .presentationDetents([.medium])
        .presentationBackground(DesignSystem.Colors.background)
    }
}

#Preview("Routine cap") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PaywallPlaceholderView(placement: .routineCap)
        }
        .preferredColorScheme(.dark)
}
