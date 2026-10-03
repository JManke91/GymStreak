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
            guidanceRules: program.guidanceRuleKeys.enumerated().map { index, stem in
                GuidanceRule(
                    id: stem,
                    number: "\(index + 1)",
                    title: "\(key).rule.\(stem).title".localized,
                    detail: "\(key).rule.\(stem).detail".localized,
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
            },
            basedOn: program.sourceKeys.map { stem in
                SourceLine(
                    id: stem,
                    name: "\(key).source.\(stem).name".localized,
                    role: "\(key).source.\(stem).role".localized
                )
            }
        )
    }

    private static func routineSummary(for routine: RoutineProgramRoutine) -> RoutineSummary {
        let exercises = routine.exercises
        let rows = exercises.enumerated().map { index, slot in
            ExerciseRow(
                id: index,
                name: slot.exerciseSeedKey.localized,
                note: note(for: slot, in: exercises),
                scheme: "\(slot.setCount) × \(slot.repMin)–\(slot.repMax)"
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

    private static func note(for slot: RoutineProgramExercise, in exercises: [RoutineProgramExercise]) -> String? {
        if !slot.alternativeSeedKeys.isEmpty {
            let names = slot.alternativeSeedKeys.map(\.localized).formatted(.list(type: .and))
            return String(format: "routine_programs.alternatives".localized, names)
        }
        if let group = slot.supersetGroup,
           let partner = exercises.first(where: { $0.supersetGroup == group && $0.exerciseSeedKey != slot.exerciseSeedKey }) {
            return String(format: "routine_programs.superset_with".localized, partner.exerciseSeedKey.localized)
        }
        return slot.noteKey?.localized
    }
}
