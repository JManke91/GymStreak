//
//  ConditioningSession.swift
//  GymStreak
//
//  The vocabulary of fight conditioning: what a session is made of and how it
//  is configured. Content (the corrected protocol) lives in
//  `ConditioningLibrary`; turning a definition into timed phases lives in
//  `ConditioningTimeline`. See docs/fight-conditioning.md.
//

import Foundation

/// The energy system a session emphasizes — the three blocks of the program.
enum ConditioningEnergySystem: String, CaseIterable, Sendable {
    case aerobic, lactic, alactic
}

/// The machine or implement a session is done on. It decides the Apple Health
/// activity type, never the session's structure.
enum ConditioningModality: String, CaseIterable, Identifiable, Sendable {
    case run, assaultBike, rower, swim, sledRopesMedBall

    var id: String { rawValue }
}

/// How much of a session the user picked.
enum ConditioningVolume: Equatable, Sendable {
    /// Steady state: the options are total minutes.
    case minutes([Int])
    /// One block of intervals: the options are rounds.
    case rounds([Int])
    /// Sets of repetitions separated by a longer break: the options are sets.
    case sets([Int], repsPerSet: Int)

    var options: [Int] {
        switch self {
        case .minutes(let options), .rounds(let options), .sets(let options, _): options
        }
    }
}

/// One session of the corrected protocol.
struct ConditioningSessionDefinition: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case aerobicBase, aerobicBursts, lactic30, lactic45, alacticPower
    }

    let id: ID
    let energySystem: ConditioningEnergySystem
    let warmUp: TimeInterval
    let coolDown: TimeInterval
    /// Length of one work interval; `nil` for steady state.
    let work: TimeInterval?
    let rest: TimeInterval
    /// Break between sets; only meaningful for `.sets` volume.
    let setBreak: TimeInterval
    let effort: ConditioningEffort
    let volume: ConditioningVolume
    /// The first (lowest) option is the default — beginners start low.
    var defaultVolume: Int { volume.options.first ?? 1 }
    /// Whether the 85–90 % beginner variant can be picked.
    let supportsSubMaximal: Bool
    let modalities: [ConditioningModality]

    var isSteadyState: Bool { work == nil }
}

/// What the user picked in the preview.
struct ConditioningSessionOptions: Equatable, Sendable {
    var volume: Int
    var isSubMaximal: Bool

    init(volume: Int, isSubMaximal: Bool = false) {
        self.volume = volume
        self.isSubMaximal = isSubMaximal
    }
}

/// A session ready to run: definition, options and modality.
struct ConditioningSessionPlan: Equatable, Sendable {
    let definition: ConditioningSessionDefinition
    let options: ConditioningSessionOptions
    let modality: ConditioningModality
}
