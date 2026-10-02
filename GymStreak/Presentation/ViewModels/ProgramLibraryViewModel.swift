//
//  ProgramLibraryViewModel.swift
//  GymStreak
//
//  Program library → detail → add sheet. See docs/routine-programs.md.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class ProgramLibraryViewModel {

    struct ExerciseRow: Identifiable, Equatable {
        let id: Int
        let name: String
        /// Alternatives or superset partner, when there is one.
        let note: String?
        /// "3 × 8–12".
        let scheme: String
    }

    struct RoutineSummary: Identifiable, Equatable {
        let id: String
        let name: String
        let exerciseCount: String
        /// "6 exercises · 15 sets".
        let meta: String
        let exercises: [ExerciseRow]
    }

    struct Stat: Identifiable, Equatable {
        let value: String
        let label: String
        var id: String { label }
    }

    /// Everything the library card and the detail screen show, built once —
    /// the catalog is static, so nothing here is recomputed in a `body`.
    struct ProgramSummary: Identifiable, Equatable {
        let id: String
        let level: String
        let name: String
        let shortPitch: String
        let pitch: String
        let sources: String
        let libraryStats: [Stat]
        let detailStats: [Stat]
        let routines: [RoutineSummary]
        let cadenceDays: Int
    }

    struct PreviewLine: Identifiable, Equatable {
        let id: String
        let routineName: String
        /// "Today, then every 4 days".
        let schedule: String
    }

    private static let logger = Logger(subsystem: LogSubsystem.sync, category: "RoutineProgramInstall")

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    let summaries: [ProgramSummary]
    /// Per program id, the routines an install would add right now.
    private(set) var routinesToAdd: [String: [RoutineProgramRoutine]] = [:]
    var didFailToInstall = false

    private let installer: any RoutineProgramInstalling
    private let proEntitlements: any ProEntitlementProviding
    private let isGatingEnabled: Bool
    private let calendar: Calendar
    private let now: () -> Date

    init(
        installer: any RoutineProgramInstalling,
        proEntitlements: any ProEntitlementProviding,
        isGatingEnabled: Bool = ProGating.isEnabled,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.installer = installer
        self.proEntitlements = proEntitlements
        self.isGatingEnabled = isGatingEnabled
        self.calendar = calendar
        self.now = now
        self.summaries = RoutineProgramCatalog.programs.map { Self.summary(for: $0) }
        refresh()
    }

    /// The "doesn't use your routine slots" lines are only true — and only
    /// interesting — for a user the P1 cap applies to. Founders are Pro.
    var showsFreeAllowanceNote: Bool {
        RoutineCapPolicy.isSubjectToCap(isPro: proEntitlements.isPro, isGatingEnabled: isGatingEnabled)
    }

    func refresh() {
        let installed = installer.installedRoutineKeys()
        routinesToAdd = Dictionary(uniqueKeysWithValues: RoutineProgramCatalog.programs.map { program in
            (program.id, program.routines.filter { !installed.contains($0.seedKey) })
        })
    }

    func isFullyInstalled(_ programId: String) -> Bool {
        routinesToAdd[programId]?.isEmpty ?? false
    }

    /// The routines the add sheet lists, as summaries.
    func pendingRoutines(of summary: ProgramSummary) -> [RoutineSummary] {
        let keys = Set((routinesToAdd[summary.id] ?? []).map(\.seedKey))
        return summary.routines.filter { keys.contains($0.id) }
    }

    func previewLines(for programId: String, choice: ProgramStartChoice) -> [PreviewLine] {
        guard let program = RoutineProgramCatalog.program(withId: programId) else { return [] }
        let routines = routinesToAdd[programId] ?? []
        let firstDay = RoutineProgramSchedule.firstWorkoutDay(for: choice, now: now(), calendar: calendar)
        return RoutineProgramSchedule.firstDueDates(for: routines, firstWorkoutDay: firstDay, calendar: calendar)
            .map { start in
                PreviewLine(
                    id: start.seedKey,
                    routineName: start.seedKey.localized,
                    schedule: String(
                        format: "routine_programs.sheet.preview_line".localized,
                        dayLabel(start.firstDate),
                        program.cadenceDays
                    )
                )
            }
    }

    /// - Returns: `true` once the routines are saved.
    func install(_ programId: String, planByRecoveryTime: Bool, choice: ProgramStartChoice) -> Bool {
        guard let program = RoutineProgramCatalog.program(withId: programId) else { return false }
        let firstDay = planByRecoveryTime
            ? RoutineProgramSchedule.firstWorkoutDay(for: choice, now: now(), calendar: calendar)
            : nil
        do {
            try installer.install(program, firstWorkoutDay: firstDay)
            refresh()
            return true
        } catch {
            Self.logger.error("Installing program \(programId, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            didFailToInstall = true
            return false
        }
    }

    // MARK: - Copy

    private func dayLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "date.today".localized }
        if calendar.isDateInTomorrow(date) { return "schedule.due.tomorrow".localized }
        return Self.dayFormatter.string(from: date)
    }

    private static func summary(for program: RoutineProgram) -> ProgramSummary {
        let key = "routine_programs.\(program.id)"
        return ProgramSummary(
            id: program.id,
            level: "\(key).level".localized,
            name: "\(key).name".localized,
            shortPitch: "\(key).pitch_short".localized,
            pitch: "\(key).pitch".localized,
            sources: "\(key).sources".localized,
            libraryStats: [
                Stat(value: "\(program.routines.count)", label: "routine_programs.stat.routines".localized),
                Stat(value: "\(key).stat.frequency".localized, label: "routine_programs.stat.per_week".localized),
                Stat(value: "\(key).stat.duration".localized, label: "routine_programs.stat.per_session".localized),
            ],
            detailStats: [
                Stat(value: "\(program.routines.count)", label: "routine_programs.stat.routines".localized),
                Stat(value: "\(key).stat.frequency".localized, label: "routine_programs.stat.per_week".localized),
                Stat(value: "\(key).stat.length".localized, label: "\(key).stat.length_label".localized),
            ],
            routines: program.routines.map { routineSummary(for: $0) },
            cadenceDays: program.cadenceDays
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
        return nil
    }
}
