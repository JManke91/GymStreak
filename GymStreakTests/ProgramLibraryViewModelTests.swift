//
//  ProgramLibraryViewModelTests.swift
//  GymStreakTests
//
//  The program library's free-only copy and the add sheet's preview
//  (docs/routine-programs.md).
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
private final class RecordingInstaller: RoutineProgramInstalling {
    var installedKeys: Set<String> = []
    private(set) var firstWorkoutDays: [Date?] = []

    func installedRoutineKeys() -> Set<String> { installedKeys }

    func install(_ program: RoutineProgram, firstWorkoutDay: Date?) throws -> Int {
        firstWorkoutDays.append(firstWorkoutDay)
        let missing = program.routines.filter { !installedKeys.contains($0.seedKey) }
        installedKeys.formUnion(missing.map(\.seedKey))
        return missing.count
    }
}

@MainActor
struct ProgramLibraryViewModelTests {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 15))!

    private func makeViewModel(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true,
        installer: RecordingInstaller = RecordingInstaller()
    ) -> ProgramLibraryViewModel {
        ProgramLibraryViewModel(
            installer: installer,
            proEntitlements: StubProEntitlements(state: state),
            isGatingEnabled: isGatingEnabled,
            calendar: Self.calendar,
            now: { Self.now }
        )
    }

    @Test(arguments: [
        (ProEntitlementState.free, true, true),
        (ProEntitlementState.founder, true, false),
        (ProEntitlementState.subscription, true, false),
        (ProEntitlementState.lifetime, true, false),
        (ProEntitlementState.free, false, false),
    ])
    func theFreeAllowanceNoteShowsOnlyForCappedUsers(state: ProEntitlementState, gating: Bool, expected: Bool) {
        #expect(makeViewModel(state: state, isGatingEnabled: gating).showsFreeAllowanceNote == expected)
    }

    @Test
    func previewListsOnlyTheRoutinesStillToAdd() {
        let installer = RecordingInstaller()
        installer.installedKeys = ["seed.program.full_body.a"]
        let viewModel = makeViewModel(installer: installer)

        let lines = viewModel.previewLines(for: "full_body", choice: .tomorrow)

        #expect(lines.map(\.id) == ["seed.program.full_body.b"])
        #expect(!viewModel.isFullyInstalled("full_body"))
    }

    @Test
    func installPassesTheChosenDayOnlyWhenPlanning() {
        let installer = RecordingInstaller()
        let viewModel = makeViewModel(installer: installer)

        #expect(viewModel.install("full_body", planByRecoveryTime: false, choice: .today))
        installer.installedKeys = []
        #expect(viewModel.install("full_body", planByRecoveryTime: true, choice: .tomorrow))

        let tomorrow = Self.calendar.date(byAdding: .day, value: 1, to: Self.calendar.startOfDay(for: Self.now))
        #expect(installer.firstWorkoutDays == [nil, tomorrow])
    }

    @Test
    func aFullyInstalledProgramReportsSo() {
        let installer = RecordingInstaller()
        let viewModel = makeViewModel(installer: installer)

        _ = viewModel.install("full_body", planByRecoveryTime: true, choice: .today)

        #expect(viewModel.isFullyInstalled("full_body"))
        #expect(viewModel.previewLines(for: "full_body", choice: .today).isEmpty)
    }

    // MARK: - Detail

    @Test
    func theAddButtonReflectsHowMuchOfTheProgramIsInstalled() {
        let installer = RecordingInstaller()
        let viewModel = makeViewModel(installer: installer)
        #expect(viewModel.addState(for: "full_body") == .add)

        installer.installedKeys = ["seed.program.full_body.a"]
        viewModel.refresh()
        #expect(viewModel.addState(for: "full_body") == .restore(count: 1))

        installer.installedKeys = ["seed.program.full_body.a", "seed.program.full_body.b"]
        viewModel.refresh()
        #expect(viewModel.addState(for: "full_body") == .added)
    }

    @Test
    func theTimelineStartsTodayWithAAndOutlinesOnlyToday() {
        let timeline = makeViewModel().timeline(for: "full_body")
        #expect(timeline.count == 14)
        #expect(timeline.map(\.isToday) == [true] + Array(repeating: false, count: 13))
        #expect(timeline.map { $0.label != nil } == (0..<14).map { $0 % 2 == 0 })
    }

    // MARK: - Shelf

    @Test
    func theShelfCardIsAddedWhileAnyRoutineIsInstalledAndRevertsWhenAllAreDeleted() {
        let installer = RecordingInstaller()
        let viewModel = makeViewModel(installer: installer)
        #expect(viewModel.shelfCards.map(\.id) == RoutineProgramCatalog.programs.map(\.id))
        #expect(viewModel.shelfCards.allSatisfy { !$0.isAdded })

        #expect(viewModel.install("full_body", planByRecoveryTime: false, choice: .today))
        #expect(viewModel.shelfCards.first { $0.id == "full_body" }?.isAdded == true)

        installer.installedKeys = ["seed.program.full_body.b"]
        viewModel.refresh()
        #expect(viewModel.shelfCards.first { $0.id == "full_body" }?.isAdded == true)

        installer.installedKeys = []
        viewModel.refresh()
        #expect(viewModel.shelfCards.first { $0.id == "full_body" }?.isAdded == false)
    }

    @Test
    func theShelfPatternFollowsTheCatalogCadence() {
        let card = makeViewModel().shelfCards.first { $0.id == "full_body" }
        // A · – · B · – · A · – · B: every 4 days, B two days after A.
        #expect(card?.pattern.map { $0.label != nil } == [true, false, true, false, true, false, true])
    }
}
