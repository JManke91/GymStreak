//
//  WorkoutSessionRepository.swift
//  GymStreak
//
//  Domain-layer contract for recorded workout history. Returns the `@Model`
//  type directly — see RoutineRepository.swift for why.
//

import Foundation

@MainActor
protocol WorkoutSessionRepository: AnyObject {
    /// All sessions, most recently started first.
    func fetchAll() -> [WorkoutSession]
    /// Most recent completed-session start date for each of the given routines.
    /// Bounded to one `LIMIT 1` query per routine — never a whole-history scan.
    func lastCompletedStartDates(forRoutineIds routineIds: [UUID]) -> [UUID: Date]
    /// Finds a session matching the watch-generated id, or (secondarily) the given
    /// HealthKit workout id. Used to detect duplicate/retried watch deliveries.
    func findSession(id: UUID, healthKitWorkoutId: UUID?) -> WorkoutSession?

    func insert(_ session: WorkoutSession)
    func delete(_ session: WorkoutSession)

    /// `WorkoutExercise`/`WorkoutSet` are normally attached via their parent's
    /// relationship array and cascade-insert automatically once the parent is
    /// persisted, but the existing workout-recording flow inserts them explicitly
    /// alongside the relationship append — preserved here for parity.
    func insert(_ exercise: WorkoutExercise)
    func delete(_ exercise: WorkoutExercise)
    func insert(_ set: WorkoutSet)
    func delete(_ set: WorkoutSet)

    func save() throws
}
