//
//  ConditioningProgramCoach.swift
//  GymStreak
//
//  "Today's conditioning": which program session fits today, given what this
//  week asks for and what the user already logged. Pure — the caller reads the
//  logged strength and conditioning history through repositories and hands in
//  value structs. The spacing rules come from docs/fight-conditioning.md
//  ("Around 3–5 strength sessions a week"):
//
//  - ≥ 48 h between lactic sessions;
//  - hard conditioning not on the same day as a heavy lower-body workout — an easy
//    session is preferred, otherwise the hard one is flagged "≥ 6 h later";
//  - at most 2 hard (lactic/alactic) sessions a week;
//  - one conditioning session a day;
//  - hard sparring counts as lactic: the weekly template already schedules less
//    lactic work for a sparring user (`ConditioningProgramContent`), and every hard
//    suggestion carries a "not on a hard sparring day" caution for them.
//

import Foundation

/// A logged conditioning session, as far as the program cares.
struct ConditioningLogEntry: Equatable, Sendable {
    let session: ConditioningSessionDefinition.ID?
    let energySystem: ConditioningEnergySystem
    let startTime: Date
    let endTime: Date
}

/// A logged strength workout, as far as the spacing rules care.
struct StrengthLogEntry: Equatable, Sendable {
    let endTime: Date
    let isHeavyLowerBody: Bool

    /// Muscle groups that make a workout "heavy lower body" for the spacing rule.
    static let lowerBodyMuscleGroups: Set<String> = ["Quadriceps", "Hamstrings"]
    /// Two or more exercises for the legs — one accessory lunge on an upper-body day does not count.
    static let lowerBodyExerciseThreshold = 2

    /// `exerciseMuscleGroups` holds one entry per performed exercise.
    static func isHeavyLowerBody(exerciseMuscleGroups: [[String]]) -> Bool {
        exerciseMuscleGroups.filter { !lowerBodyMuscleGroups.isDisjoint(with: $0) }.count >= lowerBodyExerciseThreshold
    }
}

struct ConditioningTargetProgress: Identifiable, Equatable, Sendable {
    let target: ConditioningProgramTarget
    let completed: Int
    var id: ConditioningSessionDefinition.ID { target.id }
    var remaining: Int { max(0, target.count - completed) }
}

enum ConditioningSuggestionCaution: Hashable, Sendable {
    /// A heavy lower-body workout was logged today: start no earlier than this.
    case afterLegWorkout(notBefore: Date)
    /// The user spars hard: keep this off sparring days and the day before.
    case sparring
}

enum ConditioningRestReason: Equatable, Sendable {
    case alreadyTrainedToday
    case weekComplete
    /// Only lactic work is left and the last lactic session is under 48 h ago.
    case lacticSpacing(until: Date)
    /// Only hard work is left and two hard sessions are already logged this week.
    case hardSessionCap
}

enum ConditioningTodaySuggestion: Equatable, Sendable {
    case session(ConditioningProgramTarget, cautions: [ConditioningSuggestionCaution])
    case rest(ConditioningRestReason)
}

enum ConditioningProgramCoach {

    static let lacticSpacing: TimeInterval = 48 * 3600
    static let hardAfterLegWorkout: TimeInterval = 6 * 3600
    static let maxHardSessionsPerWeek = 2

    /// How many of each target this week's logged sessions cover. An exact
    /// session match counts first; a session of the same energy system fills a
    /// target that is still open (a 45/180 done in a 30/120 week still is lactic work).
    static func progress(for week: ConditioningProgramWeek, weekEntries: [ConditioningLogEntry]) -> [ConditioningTargetProgress] {
        var completed = Dictionary(uniqueKeysWithValues: week.targets.map { ($0.session, 0) })
        var unmatched: [ConditioningLogEntry] = []
        for entry in weekEntries {
            if let session = entry.session,
               let target = week.targets.first(where: { $0.session == session }),
               completed[session, default: 0] < target.count {
                completed[session, default: 0] += 1
            } else {
                unmatched.append(entry)
            }
        }
        for entry in unmatched {
            if let target = week.targets.first(where: {
                $0.definition.energySystem == entry.energySystem && completed[$0.session, default: 0] < $0.count
            }) {
                completed[target.session, default: 0] += 1
            }
        }
        return week.targets.map { ConditioningTargetProgress(target: $0, completed: completed[$0.session, default: 0]) }
    }

    /// - Parameters:
    ///   - weekEntries: conditioning logged since the program week began.
    ///   - recentEntries: conditioning logged in the last few days, for the 48 h rule
    ///     (it can reach into the previous week).
    ///   - strengthToday: strength workouts that ended today.
    static func suggestion(
        week: ConditioningProgramWeek,
        weekEntries: [ConditioningLogEntry],
        recentEntries: [ConditioningLogEntry],
        strengthToday: [StrengthLogEntry],
        sparsHard: Bool,
        now: Date,
        calendar: Calendar
    ) -> ConditioningTodaySuggestion {
        if recentEntries.contains(where: { calendar.isDate($0.startTime, inSameDayAs: now) }) {
            return .rest(.alreadyTrainedToday)
        }
        let open = progress(for: week, weekEntries: weekEntries).filter { $0.remaining > 0 }.map(\.target)
        guard !open.isEmpty else { return .rest(.weekComplete) }

        let easy = open.first { !$0.isHard }
        var blockedReason: ConditioningRestReason?
        var hard: ConditioningProgramTarget?

        let hardThisWeek = weekEntries.filter { $0.energySystem != .aerobic }.count
        if hardThisWeek >= maxHardSessionsPerWeek {
            if open.contains(where: \.isHard) { blockedReason = .hardSessionCap }
        } else {
            let lastLacticEnd = recentEntries.filter { $0.energySystem == .lactic }.map(\.endTime).max()
            let lacticReadyAt = lastLacticEnd.map { $0.addingTimeInterval(lacticSpacing) }
            for target in open where target.isHard {
                if target.definition.energySystem == .lactic, let lacticReadyAt, lacticReadyAt > now {
                    blockedReason = .lacticSpacing(until: lacticReadyAt)
                    continue
                }
                hard = target
                break
            }
        }

        let legWorkoutEnd = strengthToday.filter(\.isHeavyLowerBody).map(\.endTime).max()
        if let hard {
            // A leg day: easy work fits right after lifting; hard work waits ≥ 6 h.
            if legWorkoutEnd != nil, let easy {
                return .session(easy, cautions: [])
            }
            var cautions: [ConditioningSuggestionCaution] = []
            if let legWorkoutEnd {
                cautions.append(.afterLegWorkout(notBefore: legWorkoutEnd.addingTimeInterval(hardAfterLegWorkout)))
            }
            if sparsHard { cautions.append(.sparring) }
            return .session(hard, cautions: cautions)
        }
        if let easy { return .session(easy, cautions: []) }
        return .rest(blockedReason ?? .weekComplete)
    }
}
