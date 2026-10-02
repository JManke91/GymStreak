//
//  ProgramInstallSheet.swift
//  GymStreak
//
//  "Add program" confirm sheet (design artboard 4): the routines being added,
//  the recovery-time plan (on by default), the first workout and a per-routine
//  first-date preview. See docs/routine-programs.md.
//

import SwiftUI

struct ProgramInstallSheet: View {
    let viewModel: ProgramLibraryViewModel
    let summary: ProgramLibraryViewModel.ProgramSummary
    let onInstalled: () -> Void

    private enum StartOption: Hashable, CaseIterable {
        case today, tomorrow, pickDay
    }

    @Environment(\.dismiss) private var dismiss
    @State private var planByRecoveryTime = true
    @State private var startOption: StartOption = .today
    @State private var pickedDay = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    /// Recomputed when the start changes — never in `body`.
    @State private var previewLines: [ProgramLibraryViewModel.PreviewLine] = []
    @State private var pendingRoutines: [ProgramLibraryViewModel.RoutineSummary] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: "routine_programs.sheet.title".localized, summary.name))
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .kerning(-0.5)
                            .foregroundStyle(.white)
                        Text("routine_programs.sheet.subtitle".localized)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    routineList
                    planSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .bottom) { confirmBar }
            .background(DesignSystem.Colors.card.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            pendingRoutines = viewModel.pendingRoutines(of: summary)
            refreshPreview()
        }
        .onChange(of: startOption) { refreshPreview() }
        .onChange(of: pickedDay) { refreshPreview() }
        .alert("routine_programs.sheet.error.title".localized, isPresented: Binding(
            get: { viewModel.didFailToInstall },
            set: { viewModel.didFailToInstall = $0 }
        )) {
            Button("action.close".localized, role: .cancel) {}
        } message: {
            Text("routine_programs.sheet.error.message".localized)
        }
    }

    // MARK: - Sections

    private var routineList: some View {
        VStack(spacing: 0) {
            ForEach(Array(pendingRoutines.enumerated()), id: \.element.id) { index, routine in
                HStack(spacing: 10) {
                    Text(routine.name)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(routine.exerciseCount)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                if index < pendingRoutines.count - 1 {
                    Divider().overlay(Color.white.opacity(0.07))
                }
            }
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $planByRecoveryTime.animation(DesignSystem.Animation.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("routine_programs.sheet.plan_toggle".localized)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(String(format: "routine_programs.sheet.plan_toggle_detail".localized, summary.cadenceDays))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .tint(DesignSystem.Colors.tint)

            if planByRecoveryTime {
                VStack(alignment: .leading, spacing: 6) {
                    Text("routine_programs.sheet.first_workout".localized)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Picker("routine_programs.sheet.first_workout".localized, selection: $startOption) {
                        Text("date.today".localized).tag(StartOption.today)
                        Text("schedule.due.tomorrow".localized).tag(StartOption.tomorrow)
                        Text("routine_programs.sheet.pick_day".localized).tag(StartOption.pickDay)
                    }
                    .pickerStyle(.segmented)

                    if startOption == .pickDay {
                        DatePicker(
                            "routine_programs.sheet.pick_day".localized,
                            selection: $pickedDay,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                        .tint(DesignSystem.Colors.tint)
                        .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(previewLines) { line in
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.tint)
                            Text(line.routineName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            Text(line.schedule)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(DesignSystem.Colors.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("routine_programs.sheet.plan_footnote".localized)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 8) {
            ProgramPrimaryButton(title: ctaTitle) {
                let didInstall = viewModel.install(
                    summary.id,
                    planByRecoveryTime: planByRecoveryTime,
                    choice: startChoice
                )
                guard didInstall else { return }
                HapticManager.shared.success()
                onInstalled()
            }
            .disabled(pendingRoutines.isEmpty)

            if viewModel.showsFreeAllowanceNote {
                Text("routine_programs.sheet.free_note".localized)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(DesignSystem.Colors.card)
    }

    // MARK: - Helpers

    private var ctaTitle: String {
        pendingRoutines.count == 1
            ? "routine_programs.sheet.cta.one".localized
            : String(format: "routine_programs.sheet.cta.other".localized, pendingRoutines.count)
    }

    private var startChoice: ProgramStartChoice {
        switch startOption {
        case .today: .today
        case .tomorrow: .tomorrow
        case .pickDay: .day(pickedDay)
        }
    }

    private func refreshPreview() {
        previewLines = viewModel.previewLines(for: summary.id, choice: startChoice)
    }
}
