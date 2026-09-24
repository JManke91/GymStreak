//
//  ConditioningProgramSection.swift
//  GymStreak
//
//  The program at the top of the Conditioning screen: an invitation to the
//  showcase when the user is not enrolled; otherwise the current phase and week,
//  today's suggestion, this week's targets and the phase timeline. Renders the
//  precomputed `ConditioningProgramDashboard` only. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningProgramSection: View {
    let viewModel: ConditioningProgramViewModel
    /// Opens the session preview pre-set to a program target.
    let onStart: (ConditioningProgramTarget) -> Void
    let onShowShowcase: () -> Void

    @State private var expandedPhase: ConditioningEnergySystem?
    @State private var showingRestart = false
    @State private var showingLeaveConfirmation = false

    var body: some View {
        Group {
            if let dashboard = viewModel.dashboard {
                enrolled(dashboard)
            } else {
                invitation
            }
        }
        .sheet(isPresented: $showingRestart) {
            ConditioningProgramEnrollSheet(viewModel: viewModel) {}
        }
        .confirmationDialog(
            "conditioning.program.leave.title".localized,
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("conditioning.program.menu.leave".localized, role: .destructive) {
                expandedPhase = nil
                viewModel.leave()
            }
        } message: {
            Text("conditioning.program.leave.message".localized)
        }
    }

    // MARK: - Not enrolled

    private var invitation: some View {
        Button(action: onShowShowcase) {
            OnyxCard(isHighlighted: true) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("conditioning.program.showcase.eyebrow".localized.uppercased())
                            .font(.onyxMonoLabel)
                            .kerning(0.7)
                            .foregroundStyle(DesignSystem.Colors.tint)
                        Text("conditioning.program.showcase.title".localized)
                            .font(.onyxHeader)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("conditioning.program.invite.subtitle".localized)
                            .font(.onyxFootnote)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Enrolled

    private func enrolled(_ dashboard: ConditioningProgramDashboard) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            HStack {
                sectionLabel("conditioning.program.section".localized)
                Spacer()
                optionsMenu(dashboard)
            }
            statusCard(dashboard)

            // The phase card belongs directly under the rail that opens it — the
            // week bar and the explanation are the same three things.
            if let system = expandedPhase,
               let phase = ConditioningProgramContent.phases.first(where: { $0.system == system }) {
                ConditioningProgramPhaseCard(
                    phase: phase,
                    targets: representativeTargets(for: phase, in: dashboard),
                    isExpanded: true,
                    currentWeek: currentWeekNumber(dashboard),
                    isPast: isPast(phase, dashboard),
                    showsConnector: false,
                    onTap: { withAnimation(DesignSystem.Animation.snappy) { expandedPhase = nil } }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let suggestion = dashboard.suggestion {
                sectionLabel("conditioning.program.today".localized)
                ConditioningProgramTodayCard(suggestion: suggestion, onStart: onStart)
            }

            if !dashboard.progress.isEmpty {
                sectionLabel("conditioning.program.this_week".localized)
                // Read live, not off `dashboard.isLocked`, so a purchase made on
                // the paywall this very card raised unblurs it immediately
                // (docs/pro-subscription.md §3c).
                if viewModel.isProgramLocked {
                    lockedWeek(dashboard.progress)
                } else {
                    weekCard(dashboard.progress)
                }
            } else if case .notStarted = dashboard.status, let week = dashboard.currentWeek {
                sectionLabel("conditioning.program.first_week".localized)
                weekCard(week.targets.map { ConditioningTargetProgress(target: $0, completed: 0) })
            }

            if dashboard.isLastFreeWeek {
                OnyxCapNudge(
                    text: "conditioning.program.gate.nudge".localized(
                        viewModel.freeProgramWeeks,
                        viewModel.freeProgramWeeks
                    ),
                    used: viewModel.freeProgramWeeks,
                    limit: viewModel.freeProgramWeeks
                )
            }
        }
    }

    /// The user's **own** Phase 2–3 week, blurred rather than hidden (§3 Rule 2):
    /// the loss the unlock is measured against has to be their real plan.
    ///
    /// The subtitle and the free-residue line are handed to the lock rather than
    /// stacked around it: as siblings of the card they collided with a lock that
    /// overflowed, and the reassurance only does its §10 job inside the gate.
    private func lockedWeek(_ progress: [ConditioningTargetProgress]) -> some View {
        weekCard(progress)
            .proLocked(
                true,
                placement: .conditioningProgram,
                subtitle: "conditioning.program.gate.subtitle".localized,
                footnote: "conditioning.program.gate.free_residue".localized
            ) {
                viewModel.requestProgramUnlock()
            }
    }

    private func optionsMenu(_ dashboard: ConditioningProgramDashboard) -> some View {
        Menu {
            if case .active = dashboard.status {
                if dashboard.enrollment.isPaused {
                    Button("conditioning.program.menu.resume".localized, systemImage: "play.fill") { viewModel.resume() }
                } else {
                    Button("conditioning.program.menu.pause".localized, systemImage: "pause.fill") { viewModel.pause() }
                }
            }
            Button("conditioning.program.menu.restart".localized, systemImage: "arrow.counterclockwise") {
                showingRestart = true
            }
            Button("conditioning.program.menu.leave".localized, systemImage: "xmark.circle", role: .destructive) {
                showingLeaveConfirmation = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
        .accessibilityLabel("conditioning.program.menu.label".localized)
    }

    private func statusCard(_ dashboard: ConditioningProgramDashboard) -> some View {
        OnyxCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if let week = dashboard.currentWeek {
                    let phase = ConditioningProgramContent.phase(ofWeek: week.number)
                    Text(ConditioningProgramCopy.phaseLabel(phase).uppercased())
                        .font(.onyxMonoLabel)
                        .kerning(0.7)
                        .foregroundStyle(ConditioningProgramPhaseCard.accent(phase.system))
                }
                Text(ConditioningProgramCopy.status(dashboard.status))
                    .font(.onyxTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                if let detail = statusDetail(dashboard) {
                    Text(detail)
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ConditioningProgramWeekRail(
                    selected: expandedPhase,
                    current: dashboard.currentWeek?.phase,
                    currentWeek: completedWeeks(dashboard),
                    onSelect: { system in
                        withAnimation(DesignSystem.Animation.snappy) {
                            expandedPhase = expandedPhase == system ? nil : system
                        }
                    }
                )
                if expandedPhase == nil {
                    Text("conditioning.program.phase.hint".localized)
                        .font(.onyxCaption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                if case .completed = dashboard.status {
                    Button("conditioning.program.menu.restart".localized) { showingRestart = true }
                        .buttonStyle(.onyxProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusDetail(_ dashboard: ConditioningProgramDashboard) -> String? {
        switch dashboard.status {
        case .notStarted: return "conditioning.program.status.not_started.detail".localized
        case .completed: return "conditioning.program.status.completed.detail".localized
        case .active:
            if dashboard.enrollment.isPaused { return "conditioning.program.status.paused.detail".localized }
            guard let week = dashboard.currentWeek else { return nil }
            let phase = ConditioningProgramCopy.phaseTitle(week.phase)
            return week.isTaper ? phase + " · " + "conditioning.program.status.taper".localized : phase
        }
    }

    private func weekCard(_ progress: [ConditioningTargetProgress]) -> some View {
        OnyxCard {
            VStack(spacing: DesignSystem.Spacing.md) {
                // At most three targets — a plain stack is fine.
                ForEach(progress) { item in
                    Button {
                        onStart(item.target)
                    } label: {
                        ConditioningTargetProgressRow(progress: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Derived

    private func currentWeekNumber(_ dashboard: ConditioningProgramDashboard) -> Int? {
        if case .active(let week, _, _) = dashboard.status { return week }
        return nil
    }

    private func completedWeeks(_ dashboard: ConditioningProgramDashboard) -> Int {
        switch dashboard.status {
        case .notStarted: 0
        case .active(let week, _, _): week
        case .completed: ConditioningProgramContent.weekCount
        }
    }

    private func isPast(_ phase: ConditioningProgramPhase, _ dashboard: ConditioningProgramDashboard) -> Bool {
        if case .completed = dashboard.status { return true }
        return currentWeekNumber(dashboard).map { $0 > phase.weeks.upperBound } ?? false
    }

    /// The user's own targets: this week's for the current phase, the phase's first week otherwise.
    private func representativeTargets(
        for phase: ConditioningProgramPhase,
        in dashboard: ConditioningProgramDashboard
    ) -> [ConditioningProgramTarget] {
        let week = currentWeekNumber(dashboard).flatMap { phase.weeks.contains($0) ? $0 : nil } ?? phase.weeks.lowerBound
        return dashboard.weeks.first { $0.number == week }?.targets ?? []
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.onyxMonoLabel)
            .kerning(0.7)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
    }
}
