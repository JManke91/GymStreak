//
//  MatSessionRunnerView.swift
//  GymStreakWatch Watch App
//
//  A mat session in progress on the watch (positioning ticket 05,
//  docs/fight-conditioning.md): the conditioning runner's pager — Pause/End one
//  swipe to the left — with elapsed time and live heart rate on the main page,
//  then the review and the saved screen. Every value comes from
//  `WatchMatSessionViewModel`; this view computes nothing.
//

import SwiftUI

struct MatSessionRunnerView: View {
    @Environment(WatchMatSessionViewModel.self) private var mat
    @State private var isConfirmingEnd = false
    /// Acted on only once the dialog is gone (the runner's end-after-dismissal pattern).
    @State private var isEndConfirmed = false
    @State private var page: Page = .live

    private enum Page: Hashable { case controls, live }

    var body: some View {
        Group {
            switch mat.state {
            case .idle, .saving:
                ProgressView()
            case .couldNotStart:
                ScrollView {
                    VStack(spacing: OnyxWatch.Spacing.md) {
                        Text("Couldn't start the session").font(.watchHeader).multilineTextAlignment(.center)
                        Text("Another workout is still running on this watch. Try again in a moment.")
                            .font(.watchCaption)
                            .foregroundStyle(OnyxWatch.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Done") { mat.dismissRunner() }
                    }
                }
            case .running, .paused:
                TabView(selection: $page) {
                    ConditioningControlsPage(
                        title: WatchMatSessionCopy.sport(mat.sport),
                        subtitle: String(localized: "\(WatchConditioningCopy.clock(mat.elapsed)) elapsed"),
                        isPaused: mat.state == .paused,
                        onPauseResume: {
                            if mat.state == .paused { mat.resume() } else { mat.pause() }
                            page = .live
                        },
                        onEnd: { isConfirmingEnd = true }
                    )
                    .tag(Page.controls)
                    MatSessionLivePage(
                        sport: mat.sport,
                        elapsed: mat.elapsed,
                        reading: mat.heartRateReading,
                        isPaused: mat.state == .paused
                    )
                    .tag(Page.live)
                }
                .tabViewStyle(.page)
                .confirmationDialog("End mat session?", isPresented: $isConfirmingEnd) {
                    Button("End session", role: .destructive) { isEndConfirmed = true }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text(mat.elapsed < WatchMatSessionViewModel.minimumDuration
                         ? "Under a minute, so nothing will be saved."
                         : "You'll rate how hard it was before it's saved.")
                }
                .onChange(of: isConfirmingEnd) { _, isPresented in
                    guard !isPresented, isEndConfirmed else { return }
                    isEndConfirmed = false
                    mat.end()
                }
            case .reviewing(let review):
                MatSessionReviewView(review: review, sport: mat.sport)
            case .finished(let health):
                finished(health)
            }
        }
        .background(OnyxWatch.Colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func finished(_ health: WatchMatSessionViewModel.HealthOutcome) -> some View {
        ScrollView {
            VStack(spacing: OnyxWatch.Spacing.md) {
                Image(systemName: health == .notSaved ? "xmark.circle" : "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(OnyxWatch.Colors.tint)
                Text(health == .notSaved ? "Session discarded" : "Session saved")
                    .font(.watchHeader)
                Text(healthLine(health))
                    .font(.watchCaption)
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Done") { mat.dismissRunner() }
            }
            .padding(.horizontal, OnyxWatch.Spacing.md)
        }
    }

    private func healthLine(_ health: WatchMatSessionViewModel.HealthOutcome) -> LocalizedStringKey {
        switch health {
        case .saved: "Saved to Apple Health · on its way to your iPhone"
        case .failed: "Couldn't save to Apple Health · on its way to your iPhone"
        case .notSaved: "Under a minute — nothing saved"
        }
    }
}

/// Sport, elapsed time and heart rate — sized for a glance mid-round.
private struct MatSessionLivePage: View {
    let sport: WatchMatSport
    let elapsed: TimeInterval
    let reading: ConditioningHeartRateReading
    let isPaused: Bool

    var body: some View {
        VStack(spacing: OnyxWatch.Spacing.sm) {
            Label(WatchMatSessionCopy.sport(sport), systemImage: WatchMatSessionCopy.symbol(sport))
                .font(.system(.footnote, design: .rounded).weight(.heavy))
                .foregroundStyle(isPaused ? OnyxWatch.Colors.warning : OnyxWatch.Colors.tint)
                .lineLimit(1)
            Text(WatchConditioningCopy.clock(elapsed))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: OnyxWatch.Spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(OnyxWatch.Colors.destructive)
                ConditioningHeartRateValue(reading: reading, size: 28, scale: 1)
                if reading.bpm != nil {
                    Text("bpm")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(OnyxWatch.Colors.textSecondary)
                }
            }
            if isPaused {
                Text("Paused")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(OnyxWatch.Colors.warning)
            } else if reading == .missing {
                Text("Check the fit and Health access")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
