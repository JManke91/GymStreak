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

    func insert(_ exercise: Exercise)
    func delete(_ exercise: Exercise)

    func save() throws
}
