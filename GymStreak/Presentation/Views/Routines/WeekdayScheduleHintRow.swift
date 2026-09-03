//
//  WeekdayScheduleHintRow.swift
//  GymStreak
//
//  P9's discovery surface: one inline, tappable row in the schedule planning
//  sheet, shown only to a user whose weekly cadence has slipped off its day.
//  See docs/monetization-strategy.md §2 and §8, and docs/pro-subscription.md §5f.
//

import SwiftUI

/// "Keep Leg Day on Wednesdays" — an inline row that opens the weekday-schedule
/// paywall when tapped, and does nothing at all when ignored.
///
/// **Placement C with a passive entry point, not placement D.** It borrows
/// `OnyxCapNudge`'s visual language — inline row, caption type, tint accent — but
/// it is a different thing: D "blocks nothing, opens nothing and has no CTA", and
/// this one opens something. That is also why it is a `Button` with a chevron
/// rather than a `.allowsHitTesting(false)` hint: the tap **is** the intent §8
/// requires before a paywall may be raised. Nothing here auto-presents.
///
/// The copy names the capability by naming the day, never "Go Pro" (§8 C). The
/// day it names is the one the plan *started* on — the day the user meant — so
/// the row reads as an offer to restore something rather than as an upsell.
///
/// Deliberately **not** in `DesignSystem/`: it is specific to one gate on one
/// screen, and generalising it would invite a second copy on a surface where
/// Rule 3 (never inside a workout, on the watch, or on the Live Activity) has
/// not been re-checked.
struct WeekdayScheduleHintRow: View {

    /// The routine's name, e.g. "Leg Day".
    let routineName: String
    /// ISO weekday the plan started on (1 = Monday … 7 = Sunday).
    let weekday: Int
    let onTap: () -> Void

    private var text: String {
        String(
            format: "schedule.hint.weekday_drift".localized,
            routineName,
            ScheduleFormatter.weekdayFullLabel(for: weekday)
        )
    }

    var body: some View {
        Button {
            HapticManager.shared.selection()
            onTap()
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "calendar.badge.clock")
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.tint)

                Text(text)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusMD)
                    .fill(DesignSystem.Colors.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#Preview("Weekday hint — dark") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: DesignSystem.Spacing.lg) {
            WeekdayScheduleHintRow(routineName: "Leg Day", weekday: 3) {}
            WeekdayScheduleHintRow(routineName: "Push Pull Legs Upper Body", weekday: 7) {}
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Weekday hint — large type") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        WeekdayScheduleHintRow(routineName: "Leg Day", weekday: 3) {}
            .padding()
    }
    .dynamicTypeSize(.accessibility1)
    .preferredColorScheme(.dark)
}
