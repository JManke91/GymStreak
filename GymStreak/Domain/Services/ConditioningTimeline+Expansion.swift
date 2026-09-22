//
//  ConditioningTimeline+Expansion.swift
//  GymStreak
//
//  Turning a session plan into timed phases. iOS only: it needs the session
//  definitions, while the watch receives the phases already expanded and runs
//  them with its identical copy of `ConditioningTimeline`.
//  See docs/fight-conditioning.md.
//

import Foundation

extension ConditioningTimeline {

    init(plan: ConditioningSessionPlan) {
        self.init(phases: Self.phases(for: plan.definition, options: plan.options))
    }

    static func phases(
        for definition: ConditioningSessionDefinition,
        options: ConditioningSessionOptions
    ) -> [ConditioningPhase] {
        var phases: [ConditioningPhase] = []
        if definition.warmUp > 0 {
            phases.append(ConditioningPhase(kind: .warmUp, duration: definition.warmUp, effort: .easy))
        }

        let effort = options.isSubMaximal && definition.supportsSubMaximal
            ? ConditioningEffort.subMaximal
            : definition.effort

        if let work = definition.work {
            let (sets, reps, isSetBased): (Int, Int, Bool) = switch definition.volume {
            case .sets(_, let repsPerSet): (max(1, options.volume), repsPerSet, true)
            case .rounds, .minutes: (1, max(1, options.volume), false)
            }

            for set in 1...sets {
                for round in 1...reps {
                    phases.append(ConditioningPhase(
                        kind: .work,
                        duration: work,
                        effort: effort,
                        round: round,
                        roundsPerSet: reps,
                        set: isSetBased ? set : nil,
                        totalSets: isSetBased ? sets : nil
                    ))
                    let isLastRound = round == reps
                    let isLastSet = set == sets
                    if !isLastRound {
                        phases.append(ConditioningPhase(
                            kind: .rest,
                            duration: definition.rest,
                            effort: .easy,
                            round: round,
                            roundsPerSet: reps,
                            set: isSetBased ? set : nil,
                            totalSets: isSetBased ? sets : nil
                        ))
                    } else if !isLastSet {
                        phases.append(ConditioningPhase(
                            kind: .setBreak,
                            duration: definition.setBreak,
                            effort: .easy,
                            set: set,
                            totalSets: sets
                        ))
                    }
                }
            }
        } else {
            phases.append(ConditioningPhase(
                kind: .steady,
                duration: TimeInterval(max(1, options.volume) * 60),
                effort: effort
            ))
        }

        if definition.coolDown > 0 {
            phases.append(ConditioningPhase(kind: .coolDown, duration: definition.coolDown, effort: .easy))
        }
        return phases
    }
}
