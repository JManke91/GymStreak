//
//  FighterStrengthProgramTests.swift
//  GymStreakTests
//
//  Fighter Strength: exact content (fighter doc §3, incl. the bench / chest-pass
//  contrast superset and the alternatives), power slots without a rep-range goal
//  so no weight-increase suggestion ever fires, the every-7-days plan with B
//  three days after A, and the detail's fight-training sections
//  (docs/routine-programs.md).
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct FighterStrengthProgramTests {

    private static let program = RoutineProgramCatalog.fighterStrength
    private static let routineA = "seed.program.fighter.a"
    private static let routineB = "seed.program.fighter.b"
    private static let powerSlots: Set<String> = [
        "seed.exercise.box_jump", "seed.exercise.medicine_ball_chest_pass",
        "seed.exercise.jump_shrug", "seed.exercise.medicine_ball_rotational_throw",
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private static let firstDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!

    private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: firstDay)!
    }

    private func makeContext() throws -> ModelContext {
        let context = ModelContext(InMemoryModelContainer.make())
        let wanted = Set(Self.program.routines.flatMap { $0.exercises.flatMap { [$0.exerciseSeedKey] + $0.alternativeSeedKeys } })
        for row in SeedExerciseCatalog.entries where wanted.contains(row.seedKey) {
            context.insert(row.makeExercise())
        }
        try context.save()
        return context
    }

    private func installedRoutines() throws -> [Routine] {
        let context = try makeContext()
        try RoutineProgramInstaller(modelContext: context, calendar: Self.calendar)
            .install(Self.program, firstWorkoutDay: Self.firstDay)
        return try context.fetch(FetchDescriptor<Routine>())
    }

    private func slots(of seedKey: String, in routines: [Routine]) throws -> [RoutineExercise] {
        try #require(routines.first { $0.seedKey == seedKey }).routineExercisesList.sorted { $0.order < $1.order }
    }

    // MARK: - Content

    @Test
    func installedRoutinesMatchTheSignedOffTables() throws {
        let installed = try installedRoutines()
        #expect(Set(installed.map(\.seedKey)) == [Self.routineA, Self.routineB])

        // (exercise, sets, start reps, rep goal, rest, alternatives)
        typealias Row = (String, Int, Int, ClosedRange<Int>?, TimeInterval, [String])
        let expected: [String: [Row]] = [
            Self.routineA: [
                ("box_jump", 3, 3, nil, 90, []),
                ("barbell_back_squat", 4, 3, 3...5, 180, ["front_squat"]),
                ("barbell_bench_press", 4, 3, 3...5, 180, ["dumbbell_bench_press"]),
                ("medicine_ball_chest_pass", 4, 3, nil, 180, []),
                ("pull_up", 3, 4, 4...6, 150, ["lat_pulldown"]),
                ("bulgarian_split_squat", 2, 6, 6...8, 120, []),
                ("ab_wheel_rollout", 3, 6, 6...10, 90, []),
            ],
            Self.routineB: [
                ("jump_shrug", 4, 3, nil, 150, ["hang_power_clean"]),
                ("deadlift", 3, 3, 3...5, 180, []),
                ("overhead_press", 3, 4, 4...6, 150, ["seated_dumbbell_shoulder_press"]),
                ("pendlay_row", 3, 5, 5...6, 150, ["barbell_row"]),
                ("medicine_ball_rotational_throw", 3, 3, nil, 90, []),
                ("hanging_leg_raise", 3, 8, 8...12, 90, ["cable_crunch"]),
            ],
        ]

        for (routineKey, rows) in expected {
            let slots = try slots(of: routineKey, in: installed)
            #expect(slots.count == rows.count)
            for (slot, row) in zip(slots, rows) {
                let (exercise, sets, reps, goal, rest, alternatives) = row
                #expect(slot.exercise?.seedKey == "seed.exercise.\(exercise)")
                #expect(slot.setsList.count == sets)
                #expect(slot.setsList.allSatisfy { $0.reps == reps && $0.weight == 0 && $0.restTime == rest })
                #expect(slot.targetRepMin == goal?.lowerBound)
                #expect(slot.targetRepMax == goal?.upperBound)
                #expect(slot.alternativesList.compactMap(\.exercise?.seedKey) == alternatives.map { "seed.exercise.\($0)" })
            }
        }
    }

    @Test
    func benchAndChestPassAreOneContrastSuperset() throws {
        let slots = try slots(of: Self.routineA, in: try installedRoutines())
        let superset = slots.filter(\.isInSuperset).sorted { $0.supersetOrder < $1.supersetOrder }
        #expect(superset.map { $0.exercise?.seedKey } == ["seed.exercise.barbell_bench_press", "seed.exercise.medicine_ball_chest_pass"])
        #expect(Set(superset.map(\.supersetId)).count == 1)
    }

    @Test
    func powerSlotsNeverQualifyForAWeightIncrease() throws {
        let installed = try installedRoutines()
        let all = try slots(of: Self.routineA, in: installed) + slots(of: Self.routineB, in: installed)
        let power = all.filter { Self.powerSlots.contains($0.exercise?.seedKey ?? "") }
        #expect(power.count == Self.powerSlots.count)

        for slot in power {
            #expect(slot.targetRepMin == nil && slot.targetRepMax == nil)
            // Every set completed, far beyond any rep count: still no suggestion.
            let crushed = slot.setsList.map { _ in ProgressiveOverloadService.SetProgress(reps: 20, isCompleted: true) }
            #expect(!ProgressiveOverloadService.workoutQualifiesForIncrease(sets: crushed, targetRepMax: slot.targetRepMax))
            #expect(!ProgressiveOverloadService.templateQualifiesForIncrease(reps: slot.setsList.map { _ in 20 }, targetRepMax: slot.targetRepMax))
            for alternative in slot.alternativesList {
                #expect(alternative.targetRepMin == nil && alternative.targetRepMax == nil)
            }
        }

        // Control: a main lift at the top of its range does qualify.
        let squat = try #require(all.first { $0.exercise?.seedKey == "seed.exercise.barbell_back_squat" })
        let topSets = squat.setsList.map { _ in ProgressiveOverloadService.SetProgress(reps: 5, isCompleted: true) }
        #expect(ProgressiveOverloadService.workoutQualifiesForIncrease(sets: topSets, targetRepMax: squat.targetRepMax))
    }

    // MARK: - Plan

    @Test
    func aAndBRepeatEverySevenDaysThreeDaysApart() throws {
        let installed = try installedRoutines()
        for (key, offset) in [(Self.routineA, 0), (Self.routineB, 3)] {
            let schedule = try #require(installed.first { $0.seedKey == key }?.schedule)
            #expect(schedule.type == .everyNDays)
            #expect(schedule.intervalDays == 7)
            #expect(schedule.startDate == Self.day(offset))
        }
    }

    @Test
    func timelineAndShelfPatternAgree() {
        let days = RoutineProgramSchedule.timeline(for: Self.program, from: Self.firstDay, dayCount: 14, calendar: Self.calendar)
        let week: [String?] = [Self.routineA, nil, nil, Self.routineB, nil, nil, nil]
        #expect(days.map(\.routineSeedKey) == week + week)

        let shelf = ProgramLibraryViewModel.shelfCard(for: Self.program)
        #expect(shelf.pattern.map(\.label) == week.map { $0.map { "\($0).short".localized } })
    }

    // MARK: - Display models

    @Test
    func detailCarriesTheFightTrainingSections() throws {
        let summary = ProgramLibraryViewModel.summary(for: Self.program)

        #expect(summary.guidanceTitle == "routine_programs.fighter.guidance_title".localized)
        #expect(summary.guidanceRules.map(\.number) == ["1", "!", "2", "3"])
        #expect(summary.guidanceRules.map(\.isWarning) == [false, true, false, false])
        #expect(summary.campIntro != nil)
        #expect(summary.campPhases.map(\.id) == ["strength", "maintain", "power", "taper"])
        #expect(summary.pairsWithConditioning)
        #expect(summary.basedOn.map(\.id) == ["kostikiadis", "nsca"])

        let routineA = try #require(summary.routines.first)
        #expect(routineA.exercises.first?.scheme == "3 × 3")
        #expect(routineA.exercises[1].scheme == "4 × 3–5")

        // The other programs keep their sections as they were.
        let fullBody = ProgramLibraryViewModel.summary(for: RoutineProgramCatalog.beginnerFullBody)
        #expect(fullBody.guidanceTitle == "routine_programs.detail.how_to_train".localized)
        #expect(fullBody.guidanceRules.map(\.number) == ["1", "2", "3", "4", "5"])
        #expect(fullBody.campIntro == nil && !fullBody.pairsWithConditioning)
    }
}
