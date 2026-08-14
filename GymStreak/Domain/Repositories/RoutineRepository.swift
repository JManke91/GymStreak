//
//  RoutineRepository.swift
//  GymStreak
//
//  Domain-layer contract for Routine persistence. Returns SwiftData `@Model`
//  types directly (deliberate — see docs/architecture.md): this app treats the
//  `@Model` classes themselves as the domain models rather than mapping to
//  separate DTOs.
//

import Foundation

@MainActor
protocol RoutineRepository: AnyObject {
    /// All routines, most recently updated first.
    func fetchAll() -> [Routine]
    func fetch(id: UUID) -> Routine?
    func fetch(name: String) -> Routine?

    func insert(_ routine: Routine)
    func delete(_ routine: Routine)

    /// Explicit insertion is required when a routine slot is synthesized for an
    /// already-persisted routine so SwiftData relationships can be wired only
    /// after both sides belong to the same model context.
    func insert(_ routineExercise: RoutineExercise)

    /// `RoutineExercise` is not managed purely through the `Routine.routineExercises`
    /// relationship — callers explicitly remove it (e.g. when the user deletes an
    /// exercise from a routine, or deletes an `Exercise` that is referenced by one).
    func delete(_ routineExercise: RoutineExercise)

    /// `ExerciseSet`, `RoutineExerciseAlternative` and `AlternativeExerciseSet` are
    /// normally attached via their parent's relationship array and cascade-insert
    /// automatically once the parent is persisted. Explicit insert is only needed
    /// where a set is synthesized independently of that relationship append (see
    /// `RoutineTemplateSyncService.applyPerformedValues`); explicit delete is always needed
    /// since removing an object from a relationship array does not delete the
    /// underlying record.
    func insert(_ set: ExerciseSet)
    func delete(_ set: ExerciseSet)
    func delete(_ alternative: RoutineExerciseAlternative)
    func delete(_ set: AlternativeExerciseSet)

    /// A `RoutineSchedule` is attached via `Routine.schedule`. Explicit insert
    /// is needed when the schedule is synthesized independently of that
    /// relationship append; explicit delete is always needed to remove the
    /// underlying record when a plan is cleared.
    func insert(_ schedule: RoutineSchedule)
    func delete(_ schedule: RoutineSchedule)

    func save() throws
}
