//
//  ConditioningProgramShowcaseView.swift
//  GymStreak
//
//  What the 12-week program is: the twelve weeks as three labelled blocks, the
//  three phases as cards that expand in place, the claims
//  docs/fight-conditioning.md allows — then enrollment. Pushed from the
//  Conditioning screen. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningProgramShowcaseView: View {
    let viewModel: ConditioningProgramViewModel
    /// Called after the user enrolled, so the caller can return to the dashboard.
    let onEnrolled: () -> Void

    @State private var showingEnrollment = false
    /// The open phase card; the week rail selects it too. Phase 1 starts open.
    @State private var expandedPhase: ConditioningEnergySystem? = .aerobic

    /// A beginner's plan — the conservative promise, and the default the
    /// enrollment sheet opens on. The user's own numbers replace it once enrolled.
    private static let sampleExperience = ConditioningExperience.beginner

    private static let claims: [(symbol: String, key: String)] = [
        ("square.stack.3d.up.fill", "conditioning.program.showcase.claim.periodized"),
        ("heart.fill", "conditioning.program.showcase.claim.zones"),
        ("dumbbell.fill", "conditioning.program.showcase.claim.lifting"),
        ("chart.line.uptrend.xyaxis", "conditioning.program.showcase.claim.progress")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                hero
                phases
                sectionLabel("conditioning.program.showcase.how".localized)
                claims
                Text("conditioning.program.showcase.safety".localized)
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                HapticManager.shared.medium()
                showingEnrollment = true
            } label: {
                Text("conditioning.program.showcase.cta".localized)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignSystem.Dimensions.buttonHeight - 24)
            }
            .buttonStyle(.onyxProminent)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.background.opacity(0.92))
        }
        .sheet(isPresented: $showingEnrollment) {
            ConditioningProgramEnrollSheet(viewModel: viewModel) { onEnrolled() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("conditioning.program.showcase.eyebrow".localized.uppercased())
                .font(.onyxMonoLabel)
                .kerning(0.9)
                .foregroundStyle(DesignSystem.Colors.tint)
            Text("conditioning.program.showcase.title".localized)
                .font(.onyxDisplay)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("conditioning.program.showcase.subtitle".localized)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ConditioningProgramWeekRail(selected: expandedPhase) { system in
                withAnimation(DesignSystem.Animation.snappy) { expandedPhase = system }
            }
            .padding(.top, DesignSystem.Spacing.sm)
        }
        .padding(.top, DesignSystem.Spacing.md)
    }

    /// The same three blocks as the rail, one card each, expanding in place —
    /// so the detail sits with the phase it describes.
    private var phases: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("conditioning.program.showcase.phases".localized)
            // Three constant phases — a plain stack is fine.
            ForEach(ConditioningProgramContent.phases) { phase in
                ConditioningProgramPhaseCard(
                    phase: phase,
                    targets: ConditioningProgramContent
                        .week(number: phase.weeks.lowerBound, experience: Self.sampleExperience, sparsHard: false)
                        .targets,
                    isExpanded: expandedPhase == phase.system,
                    onTap: {
                        withAnimation(DesignSystem.Animation.snappy) {
                            expandedPhase = expandedPhase == phase.system ? nil : phase.system
                        }
                    }
                )
            }
        }
    }

    private var claims: some View {
        OnyxCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                ForEach(Self.claims, id: \.key) { claim in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        Image(systemName: claim.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.tint)
                            .frame(width: 24)
                        Text(claim.key.localized)
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.onyxMonoLabel)
            .kerning(0.7)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
    }
}

/// Start date, experience and sparring — for a first enrollment and for a restart.
struct ConditioningProgramEnrollSheet: View {
    let viewModel: ConditioningProgramViewModel
    let onEnrolled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Date()
    @State private var experience: ConditioningExperience
    @State private var sparsHard: Bool
    private let isRestart: Bool

    /// Recomputed only when a choice changes — a small derivation over constant content.
    private var summary: ConditioningExperienceSummary {
        ConditioningProgramCopy.experienceSummary(experience, sparsHard: sparsHard)
    }

    /// The inset an inset-grouped form gives its rows on iPhone.
    private static func rowInsets(bottom: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: bottom, trailing: 20)
    }

    init(viewModel: ConditioningProgramViewModel, onEnrolled: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onEnrolled = onEnrolled
        let current = viewModel.enrollment
        isRestart = current != nil
        _experience = State(initialValue: current?.experience ?? .beginner)
        _sparsHard = State(initialValue: current?.sparsHard ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "conditioning.program.enroll.start".localized,
                        selection: $startDate,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                }
                Section {
                    Picker("conditioning.program.enroll.experience".localized, selection: $experience) {
                        ForEach(ConditioningExperience.allCases, id: \.self) { option in
                            Text(ConditioningProgramCopy.experience(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    // Clearing the row background also clears the form's own gutter,
                    // so both rows restate it — otherwise the card runs edge to edge
                    // while every other row is inset.
                    .listRowInsets(Self.rowInsets(bottom: DesignSystem.Spacing.sm))

                    // The plan the choice produces, so "experienced" is not a guess.
                    ConditioningExperienceSummaryCard(summary: summary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(Self.rowInsets())
                } header: {
                    Text("conditioning.program.enroll.experience".localized)
                }
                Section {
                    Toggle("conditioning.program.enroll.sparring".localized, isOn: $sparsHard)
                        .tint(DesignSystem.Colors.tint)
                } footer: {
                    Text(sparsHard
                         ? "conditioning.program.enroll.sparring.footer.on".localized
                         : "conditioning.program.enroll.sparring.footer.off".localized)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("conditioning.program.enroll.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isRestart
                           ? "conditioning.program.menu.restart".localized
                           : "conditioning.program.enroll.confirm".localized) {
                        HapticManager.shared.success()
                        viewModel.enroll(startDate: startDate, experience: experience, sparsHard: sparsHard)
                        dismiss()
                        onEnrolled()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// What the chosen experience level means: sessions a week, and the emphasis
/// of each phase at that level.
private struct ConditioningExperienceSummaryCard: View {
    let summary: ConditioningExperienceSummary

    var body: some View {
        OnyxCard(isHighlighted: true) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    Text("\(summary.sessionsPerWeek)")
                        .font(.onyxNumberLarge)
                        .foregroundStyle(DesignSystem.Colors.tint)
                    Text("conditioning.program.enroll.sessions_per_week".localized)
                        .font(.onyxSubheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                Text(summary.intro)
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(DesignSystem.Colors.divider)

                // Three phases — a plain stack is fine.
                ForEach(summary.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.weeks.uppercased())
                                .font(.onyxMonoLabel)
                                .kerning(0.6)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text(row.title)
                                .font(.onyxFootnote)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                        Spacer(minLength: 0)
                        Text(row.value)
                            .font(.onyxNumberSmall)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                Text(summary.note)
                    .font(.onyxCaption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
