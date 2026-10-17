//
//  MatSessionRepository.swift
//  GymStreak
//
//  Domain-layer contract for logged mat sessions. Returns the `@Model` type
//  directly — see RoutineRepository.swift for why.
//

import Foundation

@MainActor
protocol MatSessionRepository: AnyObject {
    /// One session by id, for the detail screen and for delete.
    func find(id: UUID) -> MatSession?

    func insert(_ session: MatSession)
    func delete(_ session: MatSession)

    func save() throws
}
