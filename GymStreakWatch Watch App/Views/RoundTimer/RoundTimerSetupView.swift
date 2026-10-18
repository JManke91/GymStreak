//
//  RoundTimerSetupView.swift
//  GymStreakWatch Watch App
//
//  The watch's round-timer entry (positioning ticket 07,
//  docs/fight-conditioning.md "Round timer"): the row on the routine list, and
//  the setup it opens — preset, rounds, custom lengths — whose Start runs the
//  timer on the mat-session recorder. Starts from the last-used settings.
//

import SwiftUI

struct RoundTimerDestination: Hashable {}

/// The row on the routine list, below the mat session. Always offered.
struct RoundTimerEntryRow: View {
    var body: some View {
        NavigationLink(value: RoundTimerDestination()) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Round timer", systemImage: "timer")
                    .font(.headline)
                Text("BJJ, boxing, Muay Thai rounds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct RoundTimerSetupView: View {
    @Environment(WatchMatSessionViewModel.self) private var mat

    var body: some View {
        RoundTimerSetupForm(initial: mat.lastRoundTimerConfiguration)
    }
}

/// Values and bindings only: the recorder remembers what was started.
private struct RoundTimerSetupForm: View {
    @Environment(WatchMatSessionViewModel.self) private var mat
    @State private var configuration: RoundTimerConfiguration
    /// Kept apart from `configuration.rounds` so turning open-ended off restores the count.
    @State private var roundCount: Int
    @State private var isOpenEnded: Bool

    init(initial configuration: RoundTimerConfiguration) {
        _configuration = State(initialValue: configuration)
        _roundCount = State(initialValue: configuration.rounds ?? RoundTimerConfiguration.default.plannedRounds)
        _isOpenEnded = State(initialValue: configuration.isOpenEnded)
    }

    var body: some View {
        List {
            Picker("Preset", selection: $configuration.preset) {
                ForEach(RoundTimerPreset.allCases) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WatchMatSessionCopy.preset(preset))
                        Text(verbatim: WatchMatSessionCopy.roundAndRest(
                            round: preset.roundDuration ?? configuration.customRoundDuration,
                            rest: preset.restDuration ?? configuration.customRestDuration
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .tag(preset)
                }
            }

            if configuration.preset == .custom {
                Stepper(value: $configuration.customRoundDuration, in: RoundTimerConfiguration.roundDurationRange, step: 30) {
                    valueLabel("Round", WatchConditioningCopy.clock(configuration.customRoundDuration))
                }
                Stepper(value: $configuration.customRestDuration, in: RoundTimerConfiguration.restDurationRange, step: 15) {
                    valueLabel("Rest", WatchConditioningCopy.clock(configuration.customRestDuration))
                }
            }

            Toggle("Open-ended", isOn: $isOpenEnded)
            if !isOpenEnded {
                Stepper(value: $roundCount, in: RoundTimerConfiguration.roundsRange) {
                    valueLabel("Rounds", String(localized: "\(roundCount) rounds"))
                }
            }

            Button {
                configuration.rounds = isOpenEnded ? nil : roundCount
                Task { await mat.startRoundTimer(configuration) }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.watchSubheadline)
                    // Black on the tint, never white (contrast rule).
                    .foregroundStyle(OnyxWatch.Colors.textOnTint)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: OnyxWatch.Dimensions.cornerRadiusLG)
                    .fill(OnyxWatch.Colors.tint)
            )
        }
        .navigationTitle("Round timer")
    }

    private func valueLabel(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.headline)
                .monospacedDigit()
        }
    }
}
