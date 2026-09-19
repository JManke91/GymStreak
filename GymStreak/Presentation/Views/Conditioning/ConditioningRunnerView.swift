//
//  ConditioningRunnerView.swift
//  GymStreak
//
//  The in-session screen: phase, a large countdown, round/set position and
//  the effort cue. Everything shown is derived from the view model's
//  wall-clock position. Free by Rule 3 — no Pro badge anywhere in here.
//  See docs/fight-conditioning.md.
//

import SwiftUI
import UIKit

struct ConditioningRunnerView: View {
    let viewModel: ConditioningRunViewModel
    let needsSafetyAcknowledgement: Bool
    let onAcknowledgeSafety: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingEndConfirmation = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            if needsSafetyAcknowledgement {
                ConditioningSafetyView(onAcknowledge: onAcknowledgeSafety)
            } else if viewModel.state == .finished {
                ConditioningFinishedView(viewModel: viewModel) { dismiss() }
            } else {
                runner
            }
        }
        .onAppear { startIfReady() }
        .onChange(of: needsSafetyAcknowledgement) { _, _ in startIfReady() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.resynchronize() }
        }
        // Keep the screen on while training; the phone usually sits on a bike
        // or the floor, and a lock would move cues to notifications.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.end()
        }
        .alert("conditioning.runner.end.title".localized, isPresented: $showingEndConfirmation) {
            Button("conditioning.runner.end.confirm".localized, role: .destructive) {
                viewModel.end()
            }
            Button("conditioning.runner.end.cancel".localized, role: .cancel) {}
        } message: {
            Text(endMessage)
        }
    }

    private func startIfReady() {
        guard !needsSafetyAcknowledgement, viewModel.state == .ready else { return }
        viewModel.start()
    }

    private var endMessage: String {
        viewModel.timeline.hasBegunEffort(at: viewModel.elapsed)
            ? "conditioning.runner.end.message_saves".localized
            : "conditioning.runner.end.message_nothing".localized
    }

    // MARK: - Runner

    private var runner: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            header
            Spacer(minLength: 0)
            if let position = viewModel.position {
                phaseDisplay(position)
            }
            Spacer(minLength: 0)
            if let next = viewModel.nextPhase {
                Text("conditioning.runner.next".localized(
                    ConditioningCopy.phase(next.kind), ConditioningCopy.duration(next.duration)
                ))
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            ProgressView(value: viewModel.sessionProgress)
                .tint(DesignSystem.Colors.tint)
            if viewModel.backgroundCuesUnavailable {
                Label("conditioning.runner.notifications_off".localized, systemImage: "bell.slash")
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
            controls
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.sessionTitle)
                    .font(.onyxHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Label(
                    ConditioningCopy.modality(viewModel.plan.modality),
                    systemImage: ConditioningCopy.modalitySymbol(viewModel.plan.modality)
                )
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            Text(ConditioningCopy.clock(viewModel.elapsed.rounded(.down)))
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .accessibilityLabel("conditioning.runner.elapsed".localized)
                .accessibilityValue(ConditioningCopy.clock(viewModel.elapsed.rounded(.down)))
        }
    }

    private func phaseDisplay(_ position: ConditioningPosition) -> some View {
        let phase = position.phase
        let isEffort = phase.kind.isEffort
        return VStack(spacing: DesignSystem.Spacing.md) {
            Text(ConditioningCopy.phase(phase.kind))
                .font(.onyxHeader.weight(.heavy))
                .kerning(1.2)
                .foregroundStyle(isEffort ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(Capsule().fill(isEffort ? DesignSystem.Colors.tint : DesignSystem.Colors.cardElevated))

            Text(ConditioningCopy.clock(position.remainingInPhase))
                .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(viewModel.state == .paused
                                 ? DesignSystem.Colors.textTertiary
                                 : DesignSystem.Colors.textPrimary)
                .accessibilityLabel("conditioning.runner.remaining".localized)
                .accessibilityValue(ConditioningCopy.clock(position.remainingInPhase))

            if viewModel.state == .paused {
                Text("conditioning.runner.paused".localized)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }

            if let positionText = ConditioningCopy.position(phase) {
                Text(positionText)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if phase.kind == .steady {
                Text("conditioning.runner.steady_progress".localized(
                    ConditioningCopy.clock(position.elapsedInPhase.rounded(.down)),
                    ConditioningCopy.clock(phase.duration)
                ))
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Text(ConditioningCopy.effort(phase.effort))
                .font(.onyxTitle2)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEffort ? DesignSystem.Colors.tint : DesignSystem.Colors.textPrimary)

            if let target = viewModel.heartRateTarget(for: phase) {
                VStack(spacing: 2) {
                    Label(ConditioningCopy.heartRateRange(target), systemImage: "heart.fill")
                        .font(.onyxNumber)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(ConditioningCopy.heartRateBasis(target))
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button {
                HapticManager.shared.light()
                showingEndConfirmation = true
            } label: {
                Text("conditioning.runner.end".localized)
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
            }
            .buttonStyle(.onyxProminent(
                backgroundColor: DesignSystem.Colors.cardElevated,
                foregroundColor: DesignSystem.Colors.textPrimary
            ))

            Button {
                HapticManager.shared.medium()
                if viewModel.state == .paused { viewModel.resume() } else { viewModel.pause() }
            } label: {
                Label(
                    viewModel.state == .paused
                        ? "conditioning.runner.resume".localized
                        : "conditioning.runner.pause".localized,
                    systemImage: viewModel.state == .paused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
            }
            .buttonStyle(.onyxProminent)
        }
    }
}

private struct ConditioningFinishedView: View {
    let viewModel: ConditioningRunViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            Image(systemName: viewModel.endedEarly ? "flag.checkered" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.tint)
                .accessibilityHidden(true)
            Text(viewModel.endedEarly
                 ? "conditioning.finished.ended_title".localized
                 : "conditioning.finished.title".localized)
                .font(.onyxTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(ConditioningCopy.clock(viewModel.elapsed.rounded(.down)))
                .font(.onyxNumberLarge)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            if let healthText {
                Label(healthText, systemImage: "heart.fill")
                    .font(.onyxFootnote)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            Button(action: onDone) {
                Text("conditioning.finished.done".localized)
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
            }
            .buttonStyle(.onyxProminent)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var healthText: String? {
        switch viewModel.healthSaveOutcome {
        case .notSaved: nil
        case .saving: "conditioning.finished.health_saving".localized
        case .saved: "conditioning.finished.health_saved".localized
        case .failed: "conditioning.finished.health_failed".localized
        }
    }
}
