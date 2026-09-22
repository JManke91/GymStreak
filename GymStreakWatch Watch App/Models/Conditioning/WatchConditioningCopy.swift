//
//  WatchConditioningCopy.swift
//  GymStreakWatch Watch App
//
//  Localized display text for the watch conditioning runner (ticket 06,
//  docs/fight-conditioning.md). The watch localizes the synced raw values
//  itself — the same English-key String Catalog convention as the rest of the
//  target (docs/watch-localization.md) — so it follows its own language.
//  Shorter than the iPhone's copy: effort cues are the RPE alone.
//

import Foundation

enum WatchConditioningCopy {

    static func title(_ sessionType: String) -> String {
        switch sessionType {
        case "aerobicBase": String(localized: "Aerobic base")
        case "aerobicBursts": String(localized: "Aerobic + bursts")
        case "lactic30": String(localized: "Lactic 30/120")
        case "lactic45": String(localized: "Lactic 45/180")
        case "alacticPower": String(localized: "Alactic power")
        default: String(localized: "Conditioning")
        }
    }

    /// "30 min" for steady state, "6 rounds" for intervals, "2 sets" for set-based work.
    static func volume(_ session: WatchConditioningSession) -> String {
        if session.phases.contains(where: { $0.kind == .steady }) {
            return String(localized: "\(session.volume) min")
        }
        if session.phases.contains(where: { $0.totalSets != nil }) {
            return String(localized: "\(session.volume) sets")
        }
        return String(localized: "\(session.volume) rounds")
    }

    static func modality(_ raw: String) -> String {
        switch raw {
        case "run": String(localized: "Run")
        case "assaultBike": String(localized: "Assault bike")
        case "rower": String(localized: "Rower")
        case "sledRopesMedBall": String(localized: "Sled / ropes / med ball")
        default: raw
        }
    }

    static func modalitySymbol(_ raw: String) -> String {
        switch raw {
        case "run": "figure.run"
        case "assaultBike": "figure.indoor.cycle"
        case "rower": "figure.rower"
        default: "figure.highintensity.intervaltraining"
        }
    }

    static func phase(_ kind: ConditioningPhaseKind) -> String {
        switch kind {
        case .warmUp: String(localized: "WARM-UP")
        case .work: String(localized: "WORK")
        case .rest: String(localized: "REST")
        case .setBreak: String(localized: "SET BREAK")
        case .coolDown: String(localized: "COOL-DOWN")
        case .steady: String(localized: "STEADY")
        }
    }

    static func effort(_ effort: ConditioningEffort) -> String {
        switch effort {
        case .easy: String(localized: "Easy")
        case .conversational: String(localized: "RPE 3–4 · talk pace")
        case .strongBurst: String(localized: "RPE 8")
        case .hardRepeatable: String(localized: "RPE 9")
        case .maximal: String(localized: "Max effort")
        case .subMaximal: String(localized: "85–90 %")
        }
    }

    /// "Round 2/6" or "Set 1/3 · Rep 4/5"; `nil` outside the interval block.
    static func position(_ phase: ConditioningPhase) -> String? {
        if phase.kind == .setBreak, let set = phase.set, let totalSets = phase.totalSets {
            return String(localized: "Set \(set)/\(totalSets) done")
        }
        guard let round = phase.round, let rounds = phase.roundsPerSet else { return nil }
        if let set = phase.set, let totalSets = phase.totalSets {
            return String(localized: "Set \(set)/\(totalSets) · Rep \(round)/\(rounds)")
        }
        return String(localized: "Round \(round)/\(rounds)")
    }

    /// The gauge page's instruction: what to do, not what the number is. While
    /// the first reading is on its way a user with a range is told so — never the
    /// RPE-only copy, which would say they have no target.
    static func zoneInstruction(_ status: ConditioningZoneStatus?, reading: ConditioningHeartRateReading, zone: WatchHeartRateZone?) -> String {
        if zone != nil {
            switch reading {
            case .measuring: return String(localized: "Measuring heart rate…")
            case .missing: return String(localized: "No heart rate")
            case .bpm: break
            }
        }
        switch status {
        case .inZone: return String(localized: "On target")
        case .below: return String(localized: "A bit faster")
        case .above: return String(localized: "A bit easier")
        case nil: return String(localized: "RPE 3–4")
        }
    }

    /// The line under it: how far off, what to hold, or what the target is while
    /// there is no reading.
    static func zoneDetail(_ status: ConditioningZoneStatus?, reading: ConditioningHeartRateReading, zone: WatchHeartRateZone?) -> String {
        guard let zone else { return String(localized: "Keep a conversational pace") }
        switch reading {
        case .measuring:
            return String(localized: "Target \(zone.lowerBPM)–\(zone.upperBPM) bpm")
        case .missing:
            return String(localized: "Check the fit and Health access")
        case .bpm(let bpm):
            let distance = ConditioningZoneGauge.distance(of: bpm, from: zone)
            switch status {
            case .inZone, nil: return String(localized: "Hold this pace · \(zone.lowerBPM)–\(zone.upperBPM)")
            case .below: return String(localized: "\(distance) bpm to your zone")
            case .above: return String(localized: "\(distance) bpm above your zone")
            }
        }
    }

    static func zone(_ zone: WatchHeartRateZone) -> String {
        String(localized: "\(zone.lowerBPM)–\(zone.upperBPM) bpm")
    }

    /// Countdown text, "4:05" / "1:02:00".
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
