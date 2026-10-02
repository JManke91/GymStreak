//
//  ProgramComponents.swift
//  GymStreak
//
//  Small pieces shared by the program library, detail and add sheet.
//  See docs/routine-programs.md.
//

import SwiftUI

/// "< Routines" — the pushed program screens hide the navigation bar like the
/// rest of the Routines tab and draw their own back link.
struct ProgramBackLink: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            HapticManager.shared.light()
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(DesignSystem.Colors.tint)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: "routine_programs.back".localized, title))
    }
}

struct ProgramEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .kerning(0.8)
            .foregroundStyle(DesignSystem.Colors.tint)
    }
}

/// The three stat tiles of a program card or hero.
struct ProgramStatTiles: View {
    let stats: [ProgramLibraryViewModel.Stat]
    var background: Color = Color.white.opacity(0.04)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.value)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(stat.label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ProgramSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 4)
            .padding(.top, 10)
    }
}

/// The tint "Add program" / "Add 2 routines" button.
struct ProgramPrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 15.5, weight: .heavy))
            }
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(DesignSystem.Colors.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// The program screens hide the navigation bar, so nothing covers the
    /// status bar and scrolled content shows through under the clock. Paints
    /// the background behind the top safe area only. The colour must sit in a
    /// `background` of the zero-height view: `.ignoresSafeArea` cannot grow a
    /// view with a fixed `.frame(height: 0)`, so that version paints nothing.
    func programStatusBarBackground() -> some View {
        overlay(alignment: .top) {
            Color.clear
                .frame(height: 0)
                .background(DesignSystem.Colors.background.ignoresSafeArea(edges: .top))
        }
    }
}
