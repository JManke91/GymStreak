//
//  ProgramLibraryViewModel+Summaries.swift
//  GymStreak
//
//  Builds the library and detail display models from the static catalog,
//  once, in the view model's init. See docs/routine-programs.md.
//

import Foundation

extension ProgramLibraryViewModel {

    static func summary(for program: RoutineProgram) -> ProgramSummary {
        let key = "routine_programs.\(program.id)"
        let commonStats = [
            Stat(value: "\(program.routines.count)", label: "routine_programs.stat.routines".localized),
            Stat(value: "\(key).stat.frequency".localized, label: "routine_programs.stat.per_week".localized),
        ]
        let sessionStat = Stat(value: "\(key).stat.duration".localized, label: "routine_programs.stat.per_session".localized)
        return ProgramSummary(
            id: program.id,
            level: "\(key).level".localized,
            name: "\(key).name".localized,
            shortPitch: "\(key).pitch_short".localized,
            pitch: "\(key).pitch".localized,
            sources: "\(key).sources".localized,
            libraryStats: commonStats + [sessionStat],
            detailStats: commonStats + [
                program.showsLengthStat
                    ? Stat(value: "\(key).stat.length".localized, label: "\(key).stat.length_label".localized)
                    : sessionStat
            ],
            routines: program.routines.map { routineSummary(for: $0) },
            cadenceDays: program.cadenceDays,
            scheduleDetail: "\(key).schedule_detail".localized,
            timelineLegend: program.routines.map { routine in
                String(
                    format: "routine_programs.detail.schedule.legend_item".localized,
                    "\(routine.seedKey).short".localized,
                    routine.seedKey.localized
                )
            } + ["routine_programs.detail.schedule.legend_today".localized],
            alternativeHint: program.alternativeHintKey?.localized,
            guidanceTitle: program.guidanceTitleKey.localized,
            guidanceRules: guidanceRules(for: program),
            campIntro: program.phaseKeys.isEmpty ? nil : "\(key).phases_intro".localized,
            campPhases: program.phaseKeys.map { stem in
                CampPhase(
                    id: stem,
                    weeks: "\(key).phase.\(stem).weeks".localized,
                    title: "\(key).phase.\(stem).title".localized,
                    detail: "\(key).phase.\(stem).detail".localized
                )
            },
            pairsWithConditioning: program.pairsWithConditioning,
            basedOn: program.sourceKeys.map { stem in
                SourceLine(
                    id: stem,
                    name: "\(key).source.\(stem).name".localized,
                    role: "\(key).source.\(stem).role".localized
                )
            }
        )
    }

    /// Warnings show "!" and don't take a number, so the numbered rules stay 1, 2, 3.
    private static func guidanceRules(for program: RoutineProgram) -> [GuidanceRule] {
        let key = "routine_programs.\(program.id)"
        var number = 0
        return program.guidanceRuleKeys.map { stem in
            let isWarning = program.warningRuleKeys.contains(stem)
            if !isWarning { number += 1 }
            return GuidanceRule(
                id: stem,
                number: isWarning ? "!" : "\(number)",
                title: "\(key).rule.\(stem).title".localized,
                detail: "\(key).rule.\(stem).detail".localized,
                isWarning: isWarning,
                link: program.ruleLinks[stem].map { target in
                    RuleLink(
                        programId: target,
                        title: String(
                            format: "routine_programs.detail.rule_link".localized,
                            "routine_programs.\(target).name".localized
                        )
                    )
                }
            )
        }
    }

    private static func routineSummary(for routine: RoutineProgramRoutine) -> RoutineSummary {
        let exercises = routine.exercises
        let rows = exercises.enumerated().map { index, slot in
            ExerciseRow(
                id: index,
                name: slot.exerciseSeedKey.localized,
                note: note(for: slot, in: exercises),
                scheme: scheme(for: slot)
            )
        }
        let setCount = exercises.reduce(0) { $0 + $1.setCount }
        return RoutineSummary(
            id: routine.seedKey,
            name: routine.seedKey.localized,
            exerciseCount: String(format: "routine_programs.exercise_count".localized, exercises.count),
            meta: String(format: "routine_programs.routine_meta".localized, exercises.count, setCount),
            exercises: rows
        )
    }

    /// "3 × 8–12", or "3 × 3" for a slot without a rep-range goal.
    private static func scheme(for slot: RoutineProgramExercise) -> String {
        guard let repMin = slot.repMin, let repMax = slot.repMax else {
            return "\(slot.setCount) × \(slot.startReps)"
        }
        return "\(slot.setCount) × \(repMin)–\(repMax)"
    }

    private static func note(for slot: RoutineProgramExercise, in exercises: [RoutineProgramExercise]) -> String? {
        if !slot.alternativeSeedKeys.isEmpty {
            let names = slot.alternativeSeedKeys.map(\.localized).formatted(.list(type: .and))
            let alternatives = String(format: "routine_programs.alternatives".localized, names)
            return slot.noteKey.map { "\($0.localized) · \(alternatives)" } ?? alternatives
        }
        if let group = slot.supersetGroup,
           let partner = exercises.first(where: { $0.supersetGroup == group && $0.exerciseSeedKey != slot.exerciseSeedKey }) {
            return String(format: "routine_programs.superset_with".localized, partner.exerciseSeedKey.localized)
        }
        return slot.noteKey?.localized
    }
}
