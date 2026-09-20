//
//  ConditioningProgramContent.swift
//  GymStreak
//
//  The 12-week program as data: phases → weekly templates → sessions from
//  `ConditioningLibrary`. The *corrected* protocol from docs/fight-conditioning.md
//  ("Corrected default protocol"):
//
//  - Weeks 1–4, aerobic: 2–3 × aerobic base + 1 × aerobic bursts (fast-system maintenance).
//  - Weeks 5–8, lactic: 1–2 × lactic (30/120 in weeks 5–6, 45/180 in weeks 7–8),
//    keeping 1–2 aerobic sessions. Hard sparring counts as a lactic session, so a
//    user who spars hard gets one lactic session from the app.
//  - Weeks 9–11, alactic: 2 × alactic power + 1 × aerobic base. Lactic is optional in
//    the protocol only for non-sparrers, and a third hard session would break the
//    "at most 2 hard sessions a week" rule — so it is left out.
//  - Week 12: taper — 1 × alactic at the low set count + 1 short aerobic base.
//
//  Beginners get fewer sessions and the low volume option; experienced users the middle one.
//

import Foundation

enum ConditioningProgramContent {

    static let weekCount = 12
    static let daysPerWeek = 7

    static let phases: [ConditioningProgramPhase] = [
        ConditioningProgramPhase(system: .aerobic, weeks: 1...4),
        ConditioningProgramPhase(system: .lactic, weeks: 5...8),
        ConditioningProgramPhase(system: .alactic, weeks: 9...12)
    ]

    /// 1-based position of a phase in the program.
    static func number(of phase: ConditioningProgramPhase) -> Int {
        (phases.firstIndex(of: phase) ?? 0) + 1
    }

    static func phase(ofWeek week: Int) -> ConditioningProgramPhase {
        phases.first { $0.weeks.contains(week) } ?? phases[phases.count - 1]
    }

    /// All twelve weeks for this user.
    static func weeks(experience: ConditioningExperience, sparsHard: Bool) -> [ConditioningProgramWeek] {
        (1...weekCount).map { week(number: $0, experience: experience, sparsHard: sparsHard) }
    }

    static func week(number: Int, experience: ConditioningExperience, sparsHard: Bool) -> ConditioningProgramWeek {
        let phase = phase(ofWeek: number).system
        let isTaper = number == weekCount
        let isBeginner = experience == .beginner
        let targets: [ConditioningProgramTarget]

        switch phase {
        case .aerobic:
            targets = [
                target(.aerobicBase, count: isBeginner ? 2 : 3, experience: experience),
                target(.aerobicBursts, count: 1, experience: experience)
            ]
        case .lactic:
            let lactic: ConditioningSessionDefinition.ID = number <= 6 ? .lactic30 : .lactic45
            // Hard sparring already is a lactic session; beginners start with one.
            let lacticCount = (isBeginner || sparsHard) ? 1 : 2
            targets = [
                target(lactic, count: lacticCount, experience: experience),
                target(.aerobicBase, count: 3 - lacticCount, experience: experience)
            ]
        case .alactic:
            if isTaper {
                targets = [
                    target(.alacticPower, count: 1, experience: .beginner),
                    target(.aerobicBase, count: 1, experience: .beginner)
                ]
            } else {
                targets = [
                    target(.alacticPower, count: 2, experience: experience),
                    target(.aerobicBase, count: 1, experience: experience)
                ]
            }
        }
        return ConditioningProgramWeek(number: number, phase: phase, isTaper: isTaper, targets: targets)
    }

    /// Sessions the first week asks for — what the enrollment screen means by
    /// "3 sessions a week".
    static func sessionsPerWeek(experience: ConditioningExperience, sparsHard: Bool) -> Int {
        week(number: 1, experience: experience, sparsHard: sparsHard).targets.map(\.count).reduce(0, +)
    }

    /// The target carrying a phase's own energy system, taken from its first week —
    /// the one line that describes what the phase asks of this user.
    static func emphasisTarget(
        of phase: ConditioningProgramPhase,
        experience: ConditioningExperience,
        sparsHard: Bool
    ) -> ConditioningProgramTarget? {
        week(number: phase.weeks.lowerBound, experience: experience, sparsHard: sparsHard)
            .targets.first { $0.definition.energySystem == phase.system }
    }

    /// Beginners: the lowest option. Experienced: the middle one (or the highest of two).
    private static func target(
        _ id: ConditioningSessionDefinition.ID,
        count: Int,
        experience: ConditioningExperience
    ) -> ConditioningProgramTarget {
        let options = ConditioningLibrary.session(id).volume.options
        let volume = experience == .beginner ? options[0] : options[min(1, options.count - 1)]
        return ConditioningProgramTarget(session: id, count: count, volume: volume)
    }
}
