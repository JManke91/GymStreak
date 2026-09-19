//
//  HistoryDateBlock.swift
//  GymStreak
//
//  The day/month tile on the leading edge of every History list row. Shared by
//  the workout card and the conditioning card so the two line up pixel for pixel.
//

import SwiftUI

struct HistoryDateBlock: View, Equatable {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(dowText)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.45))
            Text("\(day)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(monthText.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(width: 50)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Hoisted out of `body`: these ran twice per card, per render — the dominant per-card cost
    // in the history list (docs/history-performance.md §2.1). `@MainActor` because a shared mutable
    // formatter is only safe while every access comes from a view body.
    @MainActor
    private static let dowFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return fmt
    }()

    @MainActor
    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMM")
        return fmt
    }()

    private var dowText: String {
        Self.dowFormatter.string(from: date).uppercased()
    }

    private var day: Int {
        Calendar.current.component(.day, from: date)
    }

    private var monthText: String {
        Self.monthFormatter.string(from: date)
    }
}
