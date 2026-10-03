//
//  RoutineProgramInstaller.swift
//  GymStreak
//
//  Installs a ready-made program on demand as ordinary seeded routines.
//  See docs/routine-programs.md → "Install contract".
//

import Foundation
import SwiftData

/// Writes a `RoutineProgram`'s routines into the store when the user taps
/// "Add program". Unlike `ExampleRoutineSeeder` there is no version flag and no
/// launch trigger: the user asked for exactly this program, so it is installed
/// when asked and never resurrected on its own.
///
/// - **Gap-filling only.** A routine whose `seedKey` already exists locally is
///   never inserted again — re-installing restores deleted routines, it never
///   adds a fresh copy next to an edited one (which dedup would then collapse).
/// - **Missing exercises are re-created**, not dropped: a program the user chose
///   on purpose should arrive whole. A user exercise with the catalog row's name
///   is reused first, so a library that skipped the seed for a name collision
///   does not grow a duplicate.
/// - The plan is always `everyNDays`, never `weekdays` (P9 untouched).
///
/// Insert-only, so it does not take the `HistoryStoreGate`: nothing the History
/// actor might be walking is deleted here.
@MainActor
final class RoutineProgramInstaller: RoutineProgramInstalling {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func installedRoutineKeys() -> Set<String> {
        // `!= ""`, never `.isEmpty` — the latter is always false inside `#Predicate`.
        let routines = (try? modelContext.fetch(
            FetchDescriptor<Routine>(predicate: #Predicate { $0.seedKey != "" })
        )) ?? []
        return Set(routines.map(\.seedKey))
    }

    @discardableResult
    func install(_ program: RoutineProgram, firstWorkoutDay: Date?) throws -> Int {
        let present = installedRoutineKeys()
        let missing = program.routines.filter { !present.contains($0.seedKey) }
        guard !missing.isEmpty else { return 0 }

        do {
            try insert(missing, of: program, firstWorkoutDay: firstWorkoutDay)
            try modelContext.save()
        } catch {
            // The main context is shared: anything left pending here would be
            // persisted by the next unrelated save as a half-installed program.
            modelContext.rollback()
            throw error
        }
        // Refreshes the Routines list, which syncs the watch and reconciles the
        // calendar and reminders through its ordinary fetch path.
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
        return missing.count
    }

    private func insert(_ missing: [RoutineProgramRoutine], of program: RoutineProgram, firstWorkoutDay: Date?) throws {
        let exercises = try resolveExercises(for: missing)
        let starts = firstWorkoutDay.map {
            RoutineProgramSchedule.firstDueDates(for: missing, firstWorkoutDay: $0, calendar: calendar)
        } ?? []

        for programRoutine in missing {
            let slots = programRoutine.exercises.compactMap { slot -> SeedRoutineBuilder.Slot? in
                guard let exercise = exercises[slot.exerciseSeedKey] else { return nil }
                return SeedRoutineBuilder.Slot(
                    template: SeedRoutineExercise(
                        exerciseSeedKey: slot.exerciseSeedKey,
                        setCount: slot.setCount,
                        reps: slot.startReps,
                        targetRepMin: slot.repMin,
                        targetRepMax: slot.repMax,
                        restTime: slot.restTime,
                        supersetGroup: slot.supersetGroup
                    ),
                    exercise: exercise,
                    alternatives: slot.alternativeSeedKeys.compactMap { exercises[$0] }
                )
            }
            let routine = SeedRoutineBuilder.insertRoutine(
                seedKey: programRoutine.seedKey,
                slots: slots,
                into: modelContext
            )

            if let start = starts.first(where: { $0.seedKey == programRoutine.seedKey }) {
                let schedule = RoutineSchedule(
                    type: .everyNDays,
                    intervalDays: program.cadenceDays,
                    startDate: start.firstDate
                )
                // Set the child's to-one — the side CloudKit mirrors (docs/workout-planning.md).
                schedule.routine = routine
                modelContext.insert(schedule)
            }
        }
    }

    /// Every exercise the routines need, keyed by seed key — re-creating any the
    /// user deleted from the library.
    private func resolveExercises(for routines: [RoutineProgramRoutine]) throws -> [String: Exercise] {
        let wanted = Set(routines.flatMap { routine in
            routine.exercises.flatMap { [$0.exerciseSeedKey] + $0.alternativeSeedKeys }
        })
        var exercises = try SeedRoutineBuilder.seededExercisesBySeedKey(wanted, in: modelContext)
        let absent = wanted.subtracting(exercises.keys)
        guard !absent.isEmpty else { return exercises }

        let userExercises = try modelContext.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.seedKey == "" })
        )
        let userByName = Dictionary(
            userExercises.map { (SeedExercise.normalizedName($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in SeedExerciseCatalog.entries where absent.contains(row.seedKey) {
            if let existing = userByName[SeedExercise.normalizedName(row.seedKey.localized)] {
                exercises[row.seedKey] = existing
            } else {
                let exercise = row.makeExercise()
                modelContext.insert(exercise)
                exercises[row.seedKey] = exercise
            }
        }
        return exercises
    }
}
