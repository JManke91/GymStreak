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

    /// One "How to train it" rule.
    struct GuidanceRule: Identifiable, Equatable {
        let id: String
        let number: String
        let title: String
        let detail: String
        /// The program this rule sends the user to, with its link title.
        var link: RuleLink?
    }

    struct RuleLink: Equatable {
        let programId: String
        /// "See Push / Pull / Legs".
        let title: String
    }

    /// One "Based on" line: the source and its role in the program.
    struct SourceLine: Identifiable, Equatable {
        let id: String
        let name: String
        let role: String
    }

    /// One cell of the detail screen's 14-day timeline.
    struct TimelineDay: Identifiable, Equatable {
        let id: Int
        /// "Mo".
        let weekday: String
        /// The routine's letter ("A"), nil on a rest day.
        let label: String?
        let isToday: Bool
    }

    /// What the detail screen's "Add program" buttons do.
    enum AddState: Equatable {
        case add
        /// Some routines were deleted; the sheet re-adds only those.
        case restore(count: Int)
        case added
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
        /// The "Scheduled by recovery time" explanation.
        let scheduleDetail: String
        /// "A = Full Body A", …, "outlined = today".
        let timelineLegend: [String]
        let alternativeHint: String?
        let guidanceRules: [GuidanceRule]
        let basedOn: [SourceLine]
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

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEEE")
        return formatter
    }()

    static let timelineDayCount = 14

    let summaries: [ProgramSummary]
    /// The Routines tab's shelf and empty-state rows, with their added state.
    private(set) var shelfCards: [ShelfCard]
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
        self.shelfCards = RoutineProgramCatalog.programs.map { Self.shelfCard(for: $0) }
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
        // "Added" while any of the program's routines is in the list; it reverts
        // only once all of them are deleted (the detail then offers a restore).
        let added = Set(RoutineProgramCatalog.programs.filter { program in
            program.routines.contains { installed.contains($0.seedKey) }
        }.map(\.id))
        let cards = shelfCards.map { card in
            var card = card
            card.isAdded = added.contains(card.id)
            return card
        }
        // Runs on every Routines refetch; `@Observable` invalidates on any set.
        if cards != shelfCards { shelfCards = cards }
    }

    func summary(withId programId: String) -> ProgramSummary? {
        summaries.first { $0.id == programId }
    }

    func isFullyInstalled(_ programId: String) -> Bool {
        routinesToAdd[programId]?.isEmpty ?? false
    }

    func addState(for programId: String) -> AddState {
        guard let program = RoutineProgramCatalog.program(withId: programId),
              let missing = routinesToAdd[programId] else { return .add }
        if missing.isEmpty { return .added }
        return missing.count == program.routines.count ? .add : .restore(count: missing.count)
    }

    /// The next 14 days from today as if the whole program started today.
    /// Depends on the date, so the detail screen asks for it on appear rather
    /// than reading it from the static summary.
    func timeline(for programId: String) -> [TimelineDay] {
        guard let program = RoutineProgramCatalog.program(withId: programId) else { return [] }
        let today = now()
        return RoutineProgramSchedule.timeline(
            for: program,
            from: today,
            dayCount: Self.timelineDayCount,
            calendar: calendar
        )
        .enumerated()
        .map { index, day in
            TimelineDay(
                id: index,
                weekday: Self.weekdayFormatter.string(from: day.date),
                label: day.routineSeedKey.map { "\($0).short".localized },
                isToday: index == 0
            )
        }
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
}
