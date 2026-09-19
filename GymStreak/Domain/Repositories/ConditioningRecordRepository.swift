//
//  ConditioningRecordRepository.swift
//  GymStreak
//
//  Domain-layer contract for recorded conditioning history. Returns the
//  `@Model` type directly — see RoutineRepository.swift for why.
//

import Foundation

@MainActor
protocol ConditioningRecordRepository: AnyObject {
    /// All records, most recently started first.
    func fetchAll() -> [ConditioningRecord]
    /// One record by id, for the detail screen and for delete. One `LIMIT 1` query.
    func find(id: UUID) -> ConditioningRecord?

    func insert(_ record: ConditioningRecord)
    func delete(_ record: ConditioningRecord)

    func save() throws
}
