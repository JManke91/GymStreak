//
//  ConditioningHistoryCardView.swift
//  GymStreak
//
//  A finished conditioning session as a row in the History list, alongside the
//  workout cards. Layout: date block | title + stats | modality glyph.
//  See docs/fight-conditioning.md.
//

import SwiftUI

/// Takes a `ConditioningCardModel`, never a `ConditioningRecord` (Performance rule 4).
/// `Equatable` over plain values, like `WorkoutCardView`, so SwiftUI can skip unchanged rows.
struct ConditioningHistoryCardView: View, Equatable {
    let card: ConditioningCardModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HistoryDateBlock(date: card.startTime)
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                metricsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            modalityGlyph
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(ConditioningCopy.recordedTitle(
                sessionType: card.sessionType,
                snapshot: card.titleSnapshot
            ))
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .lineLimit(1)

            if let energySystem = card.energySystem {
                Text(ConditioningCopy.energySystem(energySystem).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    // MARK: - Metrics

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricLabel(icon: "clock", text: ConditioningCopy.clock(card.duration))
            if !card.isSteadyState {
                metricLabel(
                    icon: "repeat",
                    text: "conditioning.history.rounds".localized(card.roundsCompleted, card.roundsPlanned)
                )
            }
            if card.endedEarly {
                metricLabel(icon: "flag.checkered", text: "conditioning.history.ended_early".localized)
            }
        }
        .foregroundStyle(Color.white.opacity(0.6))
        .font(.system(size: 12))
    }

    private func metricLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .monospacedDigit()
        }
    }

    // MARK: - Modality

    /// The conditioning row's visual anchor, where a workout card carries its completion ring —
    /// so the two kinds are told apart at a glance without a label saying so.
    @ViewBuilder
    private var modalityGlyph: some View {
        if let modality = card.modality {
            Image(systemName: ConditioningCopy.modalitySymbol(modality))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 38, height: 38)
                .background(DesignSystem.Colors.tint.opacity(0.12))
                .clipShape(Circle())
                .accessibilityLabel(ConditioningCopy.modality(modality))
        }
    }
}
