//
//  ConditioningRunnerView.swift
//  GymStreakWatch Watch App
//
//  The watch conditioning runner (ticket 06, docs/fight-conditioning.md): a
//  horizontal pager — Pause/End on the left, the runner page (heart-rate gauge
//  or phase countdown, `ConditioningRunnerPages.swift`) on the right — plus the
//  waiting, could-not-start and summary states. Every value comes from
//  `WatchConditioningRunViewModel`; this view computes nothing.
//

import SwiftUI

struct ConditioningRunnerView: View {
    @Environment(WatchConditioningRunViewModel.self) private var run
    @State private var isConfirmingEnd = false
    /// Set by the dialog's confirm button; acted on only once the dialog is gone.
    @State private var isEndConfirmed = false
    /// Controls sit one swipe to the left, like Apple's Workout app; the runner is the default.
    @State private var page: Page = .runner

    private enum Page: Hashable { case controls, runner }

    var body: some View {
        Group {
            switch run.state {
            case .idle, .waitingForWorkout:
                VStack(spacing: OnyxWatch.Spacing.md) {
                    ProgressView()
                    Text("Finishing your workout…")
                        .font(.watchCaption)
                        .foregroundStyle(OnyxWatch.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            case .couldNotStart:
                message(
                    "Couldn't start the session",
                    detail: "Another workout is still running on this watch. Try again in a moment."
                )
            case .running, .paused:
                TabView(selection: $page) {
                    ConditioningControlsPage(
                        title: WatchConditioningCopy.title(run.session?.sessionType ?? ""),
                        subtitle: String(localized: "\(WatchConditioningCopy.modality(run.modality)) · \(WatchConditioningCopy.clock(run.elapsed)) elapsed"),
                        isPaused: run.state == .paused,
                        onPauseResume: {
                            if run.state == .paused { run.resume() } else { run.pause() }
                            page = .runner
                        },
                        onEnd: { isConfirmingEnd = true }
                    )
                    .tag(Page.controls)
                    runnerPage
                        .tag(Page.runner)
                }
                .tabViewStyle(.page)
                // On the running screen only, and the session ends only after the
                // dialog has closed. Ending from inside the button swapped this view
                // to the summary while the watchOS dialog was still animating out
                // with its binding still true, which presented it a second time on
                // top of the summary (device test, 2026-09-22).
                .confirmationDialog("End session early?", isPresented: $isConfirmingEnd) {
                    Button("End session", role: .destructive) { isEndConfirmed = true }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text(run.hasBegunEffort
                         ? "What you have done so far is saved to Apple Health."
                         : "You have not started the first effort yet, so nothing will be saved.")
                }
                .onChange(of: isConfirmingEnd) { _, isPresented in
                    guard !isPresented, isEndConfirmed else { return }
                    isEndConfirmed = false
                    Task { await run.end() }
                }
            case .finished(let summary):
                ConditioningRunSummaryView(summary: summary) { run.dismissRunner() }
            }
        }
        .background(OnyxWatch.Colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Heart-rate gauge for steady state, phase countdown for everything else.
    @ViewBuilder
    private var runnerPage: some View {
        if let position = run.position {
            if run.showsZonePage {
                ConditioningZonePage(
                    phaseTitle: WatchConditioningCopy.phase(position.phase.kind),
                    reading: run.heartRateReading,
                    zone: run.zone,
                    status: run.zoneStatus,
                    remaining: position.remainingInPhase,
                    phaseDuration: position.phase.duration,
                    sessionFraction: run.sessionFraction,
                    isPaused: run.state == .paused
                )
            } else {
                ConditioningIntervalPage(
                    phase: position.phase,
                    remaining: position.remainingInPhase,
                    remainingFraction: run.phaseRemainingFraction,
                    leadInCount: run.leadInCount,
                    rounds: run.roundProgress,
                    reading: run.heartRateReading,
                    nextPhase: run.nextPhase,
                    isPaused: run.state == .paused
                )
            }
        }
    }

    private func message(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        ScrollView {
            VStack(spacing: OnyxWatch.Spacing.md) {
                Text(title).font(.watchHeader).multilineTextAlignment(.center)
                Text(detail)
                    .font(.watchCaption)
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Done") { run.dismissRunner() }
            }
        }
    }
}
