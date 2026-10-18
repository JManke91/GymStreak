//
//  RoundTimerRunnerView.swift
//  GymStreak
//
//  The round timer in progress: ROUND / REST, a large countdown that turns
//  amber for the warning, the round position and the next phase. Everything
//  shown is the view model's wall-clock position. At the end: save it as a mat
//  session, or just close it. Free by Rule 3 — no Pro surface in here.
//  See docs/fight-conditioning.md, "Round timer".
//

import SwiftUI
import UIKit

struct RoundTimerRunnerView: View {
    let viewModel: RoundTimerViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingEndConfirmation = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            if viewModel.state == .finished {
                RoundTimerFinishedView(viewModel: viewModel) { dismiss() }
            } else {
                runner
            }
        }
        .onAppear {
            // Keep the screen on: the phone sits on the mat, and a lock moves
            // the bell to notifications.
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.resynchronize() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.end()
        }
        .alert("roundtimer.runner.end.title".localized, isPresented: $showingEndConfirmation) {
            Button("roundtimer.runner.end.confirm".localized, role: .destructive) { viewModel.end() }
            Button("conditioning.runner.end.cancel".localized, role: .cancel) {}
        } message: {
            Text("roundtimer.runner.end.message".localized)
        }
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
                    RoundTimerCopy.phase(next.kind), ConditioningCopy.clock(next.duration)
                ))
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            if !viewModel.configuration.isOpenEnded {
                ProgressView(value: viewModel.sessionProgress)
                    .tint(DesignSystem.Colors.tint)
            }
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
                Text("roundtimer.title".localized)
                    .font(.onyxHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Label(
                    "\(RoundTimerCopy.preset(viewModel.configuration.preset)) · \(RoundTimerCopy.lengths(viewModel.configuration))",
                    systemImage: RoundTimerCopy.presetSymbol(viewModel.configuration.preset)
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
        let isRound = phase.kind == .work
        return VStack(spacing: DesignSystem.Spacing.md) {
            Text(RoundTimerCopy.phase(phase.kind))
                .font(.onyxHeader.weight(.heavy))
                .kerning(1.2)
                .foregroundStyle(isRound ? DesignSystem.Colors.textOnTint : DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(Capsule().fill(isRound ? DesignSystem.Colors.tint : DesignSystem.Colors.cardElevated))

            Text(ConditioningCopy.clock(position.remainingInPhase))
                .font(.system(size: 110, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(countdownColor)
                .accessibilityLabel("conditioning.runner.remaining".localized)
                .accessibilityValue(ConditioningCopy.clock(position.remainingInPhase))

            if viewModel.state == .paused {
                Text("conditioning.runner.paused".localized)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }

            if let positionText = RoundTimerCopy.position(phase) {
                Text(positionText)
                    .font(.onyxTitle2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var countdownColor: Color {
        if viewModel.state == .paused { return DesignSystem.Colors.textTertiary }
        return viewModel.isInWarning ? DesignSystem.Colors.warning : DesignSystem.Colors.textPrimary
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

/// The end of a run: rounds and time, "Save as mat session" (a pre-filled
/// mat-session form) or Done. Declining leaves no trace.
private struct RoundTimerFinishedView: View {
    let viewModel: RoundTimerViewModel
    let onDone: () -> Void

    @State private var matSessionLog: MatSessionLogViewModel?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            Image(systemName: viewModel.endedEarly ? "flag.checkered" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.tint)
                .accessibilityHidden(true)
            Text(viewModel.endedEarly
                 ? "roundtimer.finished.ended_title".localized
                 : "roundtimer.finished.title".localized)
                .font(.onyxTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(RoundTimerCopy.completed(rounds: viewModel.completedRounds, elapsed: viewModel.elapsed))
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            if viewModel.hasSavedMatSession {
                Label("roundtimer.finished.saved".localized, systemImage: "checkmark")
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            Spacer()
            if viewModel.canSaveAsMatSession {
                Button {
                    HapticManager.shared.light()
                    matSessionLog = viewModel.matSessionLog()
                } label: {
                    Label(
                        "roundtimer.finished.save".localized,
                        systemImage: MatSessionCopy.sportSymbol(viewModel.matSport)
                    )
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
                }
                .buttonStyle(.onyxProminent)
            }
            Button(action: onDone) {
                Text("conditioning.finished.done".localized)
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.Dimensions.buttonHeight - 24)
            }
            .buttonStyle(viewModel.canSaveAsMatSession
                         ? .onyxProminent(
                            backgroundColor: DesignSystem.Colors.cardElevated,
                            foregroundColor: DesignSystem.Colors.textPrimary
                         )
                         : .onyxProminent)
        }
        .padding(DesignSystem.Spacing.lg)
        .sheet(item: $matSessionLog) { log in
            MatSessionLogView(viewModel: log, onSave: viewModel.didSaveMatSession)
        }
    }
}
