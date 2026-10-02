//
//  ProgramLibraryView.swift
//  GymStreak
//
//  The program library (design artboard 2). See docs/routine-programs.md.
//

import SwiftUI

struct ProgramLibraryView: View {
    let viewModel: ProgramLibraryViewModel
    /// Called once a program's routines are saved; the Routines tab pops back to
    /// its list so the user sees them land.
    let onInstalled: () -> Void

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                // The catalog is a small, bounded literal set — not user-scaled data.
                VStack(alignment: .leading, spacing: 14) {
                    ProgramBackLink(title: "routines.title".localized)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("routine_programs.library.title".localized)
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .kerning(-0.7)
                            .foregroundStyle(.white)
                        Text("routine_programs.library.intro".localized)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    ForEach(viewModel.summaries) { summary in
                        NavigationLink {
                            ProgramDetailView(viewModel: viewModel, summary: summary, onInstalled: onInstalled)
                        } label: {
                            card(summary)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { HapticManager.shared.light() })
                    }

                    if viewModel.showsFreeAllowanceNote {
                        Text("routine_programs.library.free_note".localized)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .statusBarBackground()
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .onAppear { viewModel.refresh() }
    }

    private func card(_ summary: ProgramLibraryViewModel.ProgramSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProgramEyebrow(text: summary.level)
                Spacer()
                if viewModel.isFullyInstalled(summary.id) {
                    Label("routine_programs.added".localized, systemImage: "checkmark")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.tint)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.name)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .kerning(-0.5)
                    .foregroundStyle(.white)
                Text(summary.shortPitch)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgramStatTiles(stats: summary.libraryStats)
            Text(String(format: "routine_programs.library.based_on".localized, summary.sources))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DesignSystem.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
