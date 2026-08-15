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
/// to name the thing being unlocked rather than say "Go Pro" — and, for §8's
/// value moment, the user's own accumulated figures. There is no offer here,
/// because there is no purchase surface in a shipping build until ticket 14. In
/// DEBUG it also prints the placement identifier, so the debug section proves
/// *which* placement was raised.
struct PaywallPlaceholderView: View {

    let placement: PaywallPlacement

    /// The endowed-progress figures for `.valueMoment` (§8 B). `nil` for every
    /// other placement — and never `nil` when B is on screen, because
    /// `ProactivePaywallCoordinator` does not raise B until they have loaded: a
    /// value-moment paywall showing placeholders or an off-by-one total does
    /// more damage than showing nothing.
    var lifetimeTotals: LifetimeTrainingTotals?

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

                if let figures = valueMomentFigures {
                    Text(figures)
                        .font(.onyxBody)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                }

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

    /// "You've logged 12 workouts, 148 sets and 24,300 kg of volume."
    ///
    /// `nil` unless this really is the value moment, so no other placement can
    /// accidentally acquire an endowed-progress line by being handed totals.
    private var valueMomentFigures: String? {
        guard placement == .valueMoment, let totals = lifetimeTotals else { return nil }
        return String(
            format: "paywall.value_moment.figures".localized,
            Self.counted(totals.workoutCount),
            Self.counted(totals.completedSetCount),
            Self.counted(Int(totals.volumeKilograms.rounded()))
        )
    }

    /// Hoisted to a `static let` rather than built per call — main-thread rule 2
    /// applies to every view body, not only to the ones inside a list.
    /// `@MainActor` because a shared mutable formatter is only safe while every
    /// access comes from a view body.
    @MainActor
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func counted(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview("Routine cap") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PaywallPlaceholderView(placement: .routineCap)
        }
        .preferredColorScheme(.dark)
}

#Preview("Value moment") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PaywallPlaceholderView(
                placement: .valueMoment,
                lifetimeTotals: LifetimeTrainingTotals(
                    workoutCount: 12,
                    completedSetCount: 148,
                    volumeKilograms: 24_312.5
                )
            )
        }
        .preferredColorScheme(.dark)
}
