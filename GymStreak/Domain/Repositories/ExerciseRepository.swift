//
//  ExerciseRepository.swift
//  GymStreak
//
//  Domain-layer contract for the standalone Exercise library. Returns the
//  `@Model` type directly — see RoutineRepository.swift for why.
//

import Foundation

@MainActor
protocol ExerciseRepository: AnyObject {
    /// All exercises, alphabetical by name.
    func fetchAll() -> [Exercise]
    func fetch(id: UUID) -> Exercise?

    /// Exercises sharing a non-empty seeded-library identity (`seedKey`).
    /// Returns every match so the caller can pick the deterministic surviving
    /// row exactly as `DefaultContentSeeder` does (oldest `createdAt`, then
    /// smallest `id`). A blank/empty key returns none — it is never used to
    /// resolve identity. Ticket 07 uses this to resolve a Watch-added exercise
    /// whose `Exercise.id` no longer resolves (e.g. seed dedup changed the
    /// surviving row's UUID) without ever resurrecting a deleted exercise.
    func fetchBySeedKey(_ seedKey: String) -> [Exercise]

    func insert(_ exercise: Exercise)
    func delete(_ exercise: Exercise)

    func save() throws
}
