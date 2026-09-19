//
//  ConditioningLibrary.swift
//  GymStreak
//
//  The session library — the *corrected* protocol from
//  docs/fight-conditioning.md ("Corrected default protocol"), never the source
//  numbers: no fixed BPM band, 5–8 s alactic reps with real rest, lactic work
//  at RPE 9 with the beginner-friendly low round count as the default.
//

import Foundation

enum ConditioningLibrary {

    static let sessions: [ConditioningSessionDefinition] = [
        aerobicBase, aerobicBursts, lactic30, lactic45, alacticPower
    ]

    static func session(_ id: ConditioningSessionDefinition.ID) -> ConditioningSessionDefinition {
        // `sessions` covers every `ID` case, which the library tests assert.
        sessions.first { $0.id == id }!
    }

    /// 30–60 min at RPE 3–4 / talk test. A single steady block: conversational
    /// pace already is the easy start.
    static let aerobicBase = ConditioningSessionDefinition(
        id: .aerobicBase,
        energySystem: .aerobic,
        warmUp: 0,
        coolDown: 0,
        work: nil,
        rest: 0,
        setBreak: 0,
        effort: .conversational,
        volume: .minutes([30, 45, 60]),
        supportsSubMaximal: false,
        modalities: [.run, .assaultBike, .rower, .swim]
    )

    /// Aerobic-block maintenance of the fast systems: 4–6 × 8 s at RPE 8, 90 s rest.
    static let aerobicBursts = ConditioningSessionDefinition(
        id: .aerobicBursts,
        energySystem: .aerobic,
        warmUp: 10 * 60,
        coolDown: 10 * 60,
        work: 8,
        rest: 90,
        setBreak: 0,
        effort: .strongBurst,
        volume: .rounds([4, 5, 6]),
        supportsSubMaximal: false,
        modalities: ConditioningModality.allCases
    )

    /// 30 s on / 2 min off × 6–8 at RPE 9.
    static let lactic30 = ConditioningSessionDefinition(
        id: .lactic30,
        energySystem: .lactic,
        warmUp: 10 * 60,
        coolDown: 10 * 60,
        work: 30,
        rest: 120,
        setBreak: 0,
        effort: .hardRepeatable,
        volume: .rounds([6, 7, 8]),
        supportsSubMaximal: false,
        modalities: ConditioningModality.allCases
    )

    /// 45 s on / 3 min off × 4–6 at RPE 9.
    static let lactic45 = ConditioningSessionDefinition(
        id: .lactic45,
        energySystem: .lactic,
        warmUp: 10 * 60,
        coolDown: 10 * 60,
        work: 45,
        rest: 180,
        setBreak: 0,
        effort: .hardRepeatable,
        volume: .rounds([4, 5, 6]),
        supportsSubMaximal: false,
        modalities: ConditioningModality.allCases
    )

    /// 2–3 sets × 5 reps of 8 s maximal, 90 s between reps, 4 min between sets,
    /// after a thorough warm-up. Bike and rower first: the doc's safety section
    /// prefers them for maximal efforts. No swim: all-out pool sprints are not
    /// part of the protocol.
    static let alacticPower = ConditioningSessionDefinition(
        id: .alacticPower,
        energySystem: .alactic,
        warmUp: 15 * 60,
        coolDown: 5 * 60,
        work: 8,
        rest: 90,
        setBreak: 4 * 60,
        effort: .maximal,
        volume: .sets([2, 3], repsPerSet: 5),
        supportsSubMaximal: true,
        modalities: [.assaultBike, .rower, .run, .sledRopesMedBall]
    )
}
