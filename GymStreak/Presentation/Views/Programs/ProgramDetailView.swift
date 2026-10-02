//
//  ProgramDetailView.swift
//  GymStreak
//
//  Program detail (design artboard 3): hero, recovery-time timeline, the
//  routines, the alternative hint, "How to train it", "Based on" and the
//  repeated CTA. Sections a program doesn't use are omitted.
//  See docs/routine-programs.md.
//

import SwiftUI

struct ProgramDetailView: View {
    let viewModel: ProgramLibraryViewModel
    let summary: ProgramLibraryViewModel.ProgramSummary
    /// The screen the back link returns to: the library, or the Routines tab
    /// when the program was opened from its shelf.
    var backTitle = "routine_programs.library.title".localized
    let onInstalled: () -> Void

    @State private var showingInstallSheet = false
    /// Depends on today's date, so it is fetched on appear — never built in `body`.
    @State private var timeline: [ProgramLibraryViewModel.TimelineDay] = []

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ProgramBackLink(title: backTitle)
                    hero

                    ProgramScheduleCard(detail: summary.scheduleDetail, timeline: timeline, legend: summary.timelineLegend)

                    ProgramSectionLabel(text: "routine_programs.detail.routines".localized)
                    ForEach(summary.routines) { routine in
                        routineCard(routine)
                    }

                    if let hint = summary.alternativeHint {
                        alternativeTip(hint)
                    }

                    if !summary.guidanceRules.isEmpty {
                        ProgramSectionLabel(text: "routine_programs.detail.how_to_train".localized)
                        ProgramGuidanceCard(rules: summary.guidanceRules)
                    }

                    if !summary.basedOn.isEmpty {
                        ProgramSectionLabel(text: "routine_programs.detail.based_on".localized)
                        ProgramSourcesCard(sources: summary.basedOn)
                    }

                    addButton
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .statusBarBackground()
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .onAppear { timeline = viewModel.timeline(for: summary.id) }
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

    /// Shown in the hero and repeated at the bottom.
    @ViewBuilder
    private var addButton: some View {
        switch viewModel.addState(for: summary.id) {
        case .added:
            Label("routine_programs.added".localized, systemImage: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Colors.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .add:
            ProgramPrimaryButton(title: "routine_programs.detail.add".localized, systemImage: "plus") {
                openInstallSheet()
            }
        case .restore(let count):
            let title = count == 1
                ? "routine_programs.detail.restore.one".localized
                : String(format: "routine_programs.detail.restore.other".localized, count)
            ProgramPrimaryButton(title: title, systemImage: "arrow.uturn.backward") {
                openInstallSheet()
            }
        }
    }

    private func openInstallSheet() {
        HapticManager.shared.light()
        showingInstallSheet = true
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

    private func alternativeTip(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .padding(.top, 1)
            Text(hint)
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
