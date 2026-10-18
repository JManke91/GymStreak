//
//  RoundTimerSetupViewModel.swift
//  GymStreak
//
//  The round timer's setup screen (docs/fight-conditioning.md, "Round timer"):
//  a preset, the rounds, the warning — remembered on Start, so the next visit
//  opens on what the user last ran.
//

import Foundation
import Observation

@Observable
@MainActor
final class RoundTimerSetupViewModel {

    var configuration: RoundTimerConfiguration
    /// The run in progress, presented full screen; `nil` once it is dismissed.
    var activeRun: RoundTimerViewModel?

    /// Restored when "open-ended" is switched off again.
    @ObservationIgnored private var lastFiniteRounds: Int
    @ObservationIgnored private let settings: any RoundTimerSettingsStoring
    @ObservationIgnored private let makeRun: (RoundTimerConfiguration) -> RoundTimerViewModel

    init(
        settings: any RoundTimerSettingsStoring,
        makeRun: @escaping (RoundTimerConfiguration) -> RoundTimerViewModel
    ) {
        let configuration = settings.lastUsedConfiguration ?? .default
        self.configuration = configuration
        self.lastFiniteRounds = configuration.rounds ?? RoundTimerConfiguration.default.rounds ?? 6
        self.settings = settings
        self.makeRun = makeRun
    }

    var isCustom: Bool { configuration.preset == .custom }

    var isOpenEnded: Bool {
        get { configuration.isOpenEnded }
        set {
            if newValue {
                if let rounds = configuration.rounds { lastFiniteRounds = rounds }
                configuration.rounds = nil
            } else {
                configuration.rounds = lastFiniteRounds
            }
        }
    }

    /// The round count the stepper edits; meaningful while not open-ended.
    var rounds: Int {
        get { configuration.rounds ?? lastFiniteRounds }
        set {
            configuration.rounds = newValue
            lastFiniteRounds = newValue
        }
    }

    func select(_ preset: RoundTimerPreset) {
        configuration.preset = preset
    }

    func start() {
        settings.remember(configuration)
        activeRun = makeRun(configuration)
    }
}
