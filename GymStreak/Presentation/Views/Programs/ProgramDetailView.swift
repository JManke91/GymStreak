//
//  ProgramDetailView.swift
//  GymStreak
//
//  Basic program detail (design artboard 3): hero, the routines and the
//  alternative tip. Timeline, guidance and sources arrive with ticket 03.
//  See docs/routine-programs.md.
//

import SwiftUI

struct ProgramDetailView: View {
    let viewModel: ProgramLibraryViewModel
    let summary: ProgramLibraryViewModel.ProgramSummary
    let onInstalled: () -> Void

    @State private var showingInstallSheet = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ProgramBackLink(title: "routine_programs.library.title".localized)
                    hero

                    ProgramSectionLabel(text: "routine_programs.detail.routines".localized)
                    ForEach(summary.routines) { routine in
                        routineCard(routine)
                    }

                    alternativeTip
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .sheet(isPresented: $showingInstallSheet) {
            ProgramInstallSheet(viewModel: viewModel, summary: summary) {
                showingInstallSheet = false
                onInstalled()
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgramEyebrow(text: String(format: "routine_programs.detail.eyebrow".localized, summary.level))
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.name)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .kerning(-0.8)
                    .foregroundStyle(.white)
                Text(summary.pitch)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgramStatTiles(stats: summary.detailStats, background: Color.black.opacity(0.35))
            addButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DesignSystem.Colors.tint.opacity(0.11), DesignSystem.Colors.tint.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var addButton: some View {
        if viewModel.isFullyInstalled(summary.id) {
            Label("routine_programs.detail.added".localized, systemImage: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Colors.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            ProgramPrimaryButton(title: "routine_programs.detail.add".localized, systemImage: "plus") {
                HapticManager.shared.light()
                showingInstallSheet = true
            }
        }
    }

    // MARK: - Routines

    private func routineCard(_ routine: ProgramLibraryViewModel.RoutineSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(routine.name)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(routine.meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            ForEach(routine.exercises) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        if let note = row.note {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                    }
                    Spacer(minLength: 8)
                    Text(row.scheme)
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var alternativeTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .padding(.top, 1)
            Text("routine_programs.detail.alternative_tip".localized)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
