//
//  MatSessionCardView.swift
//  GymStreak
//
//  A logged mat session as a row in the History list. Same layout as the
//  conditioning card: date block | sport + stats | sport glyph.
//  See docs/fight-conditioning.md.
//

import SwiftUI

/// Takes a `MatSessionCardModel`, never a `MatSession` (Performance rule 4).
struct MatSessionCardView: View, Equatable {
    let card: MatSessionCardModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HistoryDateBlock(date: card.startTime)
            VStack(alignment: .leading, spacing: 4) {
                Text(MatSessionCopy.sport(card.sport))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    metricLabel(icon: "clock", text: ConditioningCopy.clock(card.duration))
                    if let intensity = card.intensity {
                        metricLabel(icon: "flame", text: MatSessionCopy.intensity(intensity))
                    }
                }
                .foregroundStyle(Color.white.opacity(0.6))
                .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: MatSessionCopy.sportSymbol(card.sport))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 38, height: 38)
                .background(DesignSystem.Colors.tint.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metricLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .monospacedDigit()
        }
    }
}
