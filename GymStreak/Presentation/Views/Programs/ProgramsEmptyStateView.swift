//
//  ProgramsEmptyStateView.swift
//  GymStreak
//
//  The Routines tab with zero routines: "Start with a program" (design
//  artboard 6). See docs/routine-programs.md.
//

import SwiftUI

struct ProgramsEmptyStateView: View {
    let cards: [ProgramLibraryViewModel.ShelfCard]
    let onOpen: (String) -> Void
    let onBuildOwn: () -> Void

    var body: some View {
        ScrollView {
            // The catalog is a small, bounded literal set — not user-scaled data.
            VStack(alignment: .leading, spacing: 14) {
                Text("routines.title".localized)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .kerning(-0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("routines.empty.programs.title".localized)
                        .font(.system(size: 23, weight: .heavy, design: .rounded))
                        .kerning(-0.4)
                        .foregroundStyle(.white)
                    Text("routines.empty.programs.description".localized)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 26)
                .padding(.bottom, 6)

                ForEach(cards) { card in
                    Button {
                        HapticManager.shared.light()
                        onOpen(card.id)
                    } label: {
                        row(card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                HapticManager.shared.light()
                onBuildOwn()
            } label: {
                Label("routines.empty.build_own".localized, systemImage: "plus")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DesignSystem.Colors.tint.opacity(0.4), lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(DesignSystem.Colors.background)
        }
    }

    private func row(_ card: ProgramLibraryViewModel.ShelfCard) -> some View {
        HStack(spacing: 14) {
            Text(card.mark)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.7)
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: 44, height: 44)
                .background(DesignSystem.Colors.tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                    .kerning(-0.3)
                    .foregroundStyle(.white)
                Text(card.meta)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignSystem.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
