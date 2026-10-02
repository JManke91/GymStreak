//
//  ProgramShelf.swift
//  GymStreak
//
//  The Programs shelf on the Routines tab (design artboards 1 and 5).
//  See docs/routine-programs.md.
//

import SwiftUI

struct ProgramShelf: View {
    let cards: [ProgramLibraryViewModel.ShelfCard]
    let onOpen: (String) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("routine_programs.library.title".localized.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.7)
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text("routine_programs.shelf.subtitle".localized)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    HapticManager.shared.light()
                    onSeeAll()
                } label: {
                    Text("routine_programs.shelf.see_all".localized)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                // The catalog is a small, bounded literal set — not user-scaled data.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(cards) { card in
                        Button {
                            HapticManager.shared.light()
                            onOpen(card.id)
                        } label: {
                            ProgramShelfCard(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // Runs to the screen edge, so the next card peeks out from under it.
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
        }
    }
}

private struct ProgramShelfCard: View {
    let card: ProgramLibraryViewModel.ShelfCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if card.isAdded {
                    Label {
                        Text("routine_programs.added".localized.uppercased())
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(DesignSystem.Colors.tint)
                    }
                    .labelStyle(ShelfAddedLabelStyle())
                } else {
                    ProgramEyebrow(text: card.level)
                }
                Spacer(minLength: 0)
                Text(card.routineCount)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Text(card.name)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .kerning(-0.4)
                .foregroundStyle(.white)
            Text(card.pitch)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(3)
                .frame(minHeight: 34, alignment: .topLeading)
            HStack(spacing: 4) {
                ForEach(card.pattern) { day in
                    Text(day.label ?? "")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(day.label == nil ? Color.white.opacity(0.05) : DesignSystem.Colors.tint.opacity(0.16))
                        )
                }
            }
            .accessibilityHidden(true)
            Text(card.cadence)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(16)
        .frame(width: 248, alignment: .leading)
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

/// "✓ ADDED" in the eyebrow's place: grey text, tinted check (artboard 5).
private struct ShelfAddedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 10, weight: .heavy))
            configuration.title
                .font(.system(size: 10.5, weight: .heavy))
                .kerning(0.7)
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}
