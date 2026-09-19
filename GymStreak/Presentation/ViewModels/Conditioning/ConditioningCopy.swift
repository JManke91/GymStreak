//
//  ConditioningCopy.swift
//  GymStreak
//
//  Localized display text for the conditioning vocabulary. Shared by the
//  screens and by the runner's notification text.
//

import Foundation

enum ConditioningCopy {

    static func title(_ id: ConditioningSessionDefinition.ID) -> String {
        "conditioning.session.\(id.rawValue).title".localized
    }

    static func summary(_ id: ConditioningSessionDefinition.ID) -> String {
        "conditioning.session.\(id.rawValue).summary".localized
    }

    static func energySystem(_ system: ConditioningEnergySystem) -> String {
        "conditioning.energy.\(system.rawValue)".localized
    }

    static func modality(_ modality: ConditioningModality) -> String {
        "conditioning.modality.\(modality.rawValue)".localized
    }

    static func modalitySymbol(_ modality: ConditioningModality) -> String {
        switch modality {
        case .run: "figure.run"
        case .assaultBike: "figure.indoor.cycle"
        case .rower: "figure.rower"
        case .swim: "figure.pool.swim"
        case .sledRopesMedBall: "figure.highintensity.intervaltraining"
        }
    }

    static func effort(_ effort: ConditioningEffort) -> String {
        "conditioning.effort.\(effort.rawValue)".localized
    }

    static func phase(_ kind: ConditioningPhaseKind) -> String {
        "conditioning.phase.\(kind.rawValue)".localized
    }

    /// "Round 2 of 6" or "Set 1 of 3 · Rep 4 of 5"; `nil` for phases outside
    /// the interval block.
    static func position(_ phase: ConditioningPhase) -> String? {
        if phase.kind == .setBreak, let set = phase.set, let totalSets = phase.totalSets {
            return "conditioning.position.set_done".localized(set, totalSets)
        }
        guard let round = phase.round, let rounds = phase.roundsPerSet else { return nil }
        if let set = phase.set, let totalSets = phase.totalSets {
            return "conditioning.position.set_rep".localized(set, totalSets, round, rounds)
        }
        return "conditioning.position.round".localized(round, rounds)
    }

    /// "30 s" / "2 min" / "90 s".
    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole >= 60, whole % 60 == 0 {
            return "conditioning.unit.minutes".localized(whole / 60)
        }
        return "conditioning.unit.seconds".localized(whole)
    }

    /// Countdown clock text, "4:05" / "12:30" / "1:02:00".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
