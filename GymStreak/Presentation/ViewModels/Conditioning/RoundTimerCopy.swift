//
//  RoundTimerCopy.swift
//  GymStreak
//
//  Localized display text for the round timer, and the cue vocabulary it hands
//  the interval engine (docs/fight-conditioning.md, "Round timer").
//

import Foundation

enum RoundTimerCopy {

    static func preset(_ preset: RoundTimerPreset) -> String {
        "roundtimer.preset.\(preset.rawValue)".localized
    }

    static func presetSymbol(_ preset: RoundTimerPreset) -> String {
        switch preset {
        case .bjj, .mma: "figure.martial.arts"
        case .boxing: "figure.boxing"
        case .muayThai: "figure.kickboxing"
        case .custom: "slider.horizontal.3"
        }
    }

    /// "5:00 / 1:00" — round and rest length.
    static func lengths(_ configuration: RoundTimerConfiguration) -> String {
        "\(ConditioningCopy.clock(configuration.roundDuration)) / \(ConditioningCopy.clock(configuration.restDuration))"
    }

    /// "ROUND" / "REST".
    static func phase(_ kind: ConditioningPhaseKind) -> String {
        kind == .work ? "roundtimer.phase.round".localized : ConditioningCopy.phase(kind)
    }

    /// "Round 3 of 6", or "Round 3" when open-ended.
    static func position(_ phase: ConditioningPhase) -> String? {
        guard let round = phase.round else { return nil }
        if let rounds = phase.roundsPerSet {
            return "roundtimer.position.round".localized(round, rounds)
        }
        return "roundtimer.position.round_open".localized(round)
    }

    /// "6 rounds · 35:00" for a finite plan, "Open-ended" otherwise.
    static func summary(_ configuration: RoundTimerConfiguration) -> String {
        guard let rounds = configuration.rounds, let total = configuration.totalDuration else {
            return "roundtimer.summary.open".localized
        }
        return completed(rounds: rounds, elapsed: total)
    }

    /// "6 rounds · 35:12" — what a run actually did.
    static func completed(rounds: Int, elapsed: TimeInterval) -> String {
        let clock = ConditioningCopy.clock(elapsed.rounded(.down))
        return rounds == 1
            ? "roundtimer.summary.round_one".localized(clock)
            : "roundtimer.summary.rounds".localized(rounds, clock)
    }

    /// "10 s" / "Off".
    static func warning(_ seconds: TimeInterval) -> String {
        seconds > 0 ? ConditioningCopy.duration(seconds) : "roundtimer.setup.warning.off".localized
    }

    // MARK: - Cues

    /// Bells for round start and end, the clacker for the warning, and
    /// notifications that say which round it is.
    static func vocabulary(for configuration: RoundTimerConfiguration) -> ConditioningCueVocabulary {
        ConditioningCueVocabulary(
            phaseStart: { $0.kind == .work ? .roundStart : .roundEnd },
            startCue: .roundStart,
            finished: .roundTimerFinished,
            text: { phase in
                let position = Self.position(phase) ?? Self.phase(phase.kind)
                if phase.kind == .work {
                    return .init(
                        title: position,
                        body: "roundtimer.notification.round.body".localized(ConditioningCopy.clock(phase.duration))
                    )
                }
                return .init(
                    title: Self.phase(phase.kind),
                    body: "roundtimer.notification.rest.body".localized(
                        ConditioningCopy.clock(phase.duration), (phase.round ?? 0) + 1
                    )
                )
            },
            finishedText: .init(
                title: "roundtimer.notification.finished.title".localized,
                body: "roundtimer.notification.finished.body".localized
            ),
            warning: configuration.warning > 0
                ? .init(
                    lead: configuration.warning,
                    cue: .roundWarning,
                    text: { phase in
                        .init(
                            title: "roundtimer.notification.warning.title".localized(Int(configuration.warning)),
                            body: Self.position(phase) ?? Self.phase(phase.kind)
                        )
                    }
                )
                : nil
        )
    }
}
