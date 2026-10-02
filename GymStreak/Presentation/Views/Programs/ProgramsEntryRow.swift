//
//  ProgramsEntryRow.swift
//  GymStreak
//
//  Temporary Routines-tab entry into the program library, until the Programs
//  shelf replaces it (ticket 04). See docs/routine-programs.md.
//

import SwiftUI

struct ProgramsEntryRow: View {
    let onOpen: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.light()
            onOpen()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("routine_programs.entry.title".localized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("routine_programs.entry.subtitle".localized)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG, style: .continuous)
                    .fill(DesignSystem.Colors.card)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
