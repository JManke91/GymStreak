//
//  WorkoutShareEntryRow.swift
//  GymStreak
//
//  The completion screen's way into sharing: a live card thumbnail, one line on what gets
//  shared, and a Share button. Design: `EntrySave.dc.html` (docs/workout-sharing.md).
//

import SwiftUI

struct WorkoutShareEntryRow: View {

    let card: WorkoutShareCardModel
    let subtitle: String
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            WorkoutShareCardThumbnail(model: card, width: 81)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text("share.entry.title".localized)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onShare) {
                    Label("share.action".localized, systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textOnTint)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(DesignSystem.Colors.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DesignSystem.Colors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.22), lineWidth: 1)
        }
    }
}
