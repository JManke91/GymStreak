//
//  WatchExerciseCatalogMapper.swift
//  GymStreak
//
//  Maps the SwiftData Exercise library to the catalogue wire items. iOS-only —
//  the watch never sees the @Model type.
//

import Foundation

enum WatchExerciseCatalogMapper {
    /// Full-fidelity mapping in a deterministic order (localized
    /// case-insensitive name, UUID string as the tie-breaker) so identical
    /// libraries always produce identical snapshot content.
    static func items(from exercises: [Exercise]) -> [WatchExerciseCatalogItem] {
        exercises
            .map { exercise in
                WatchExerciseCatalogItem(
                    id: exercise.id,
                    seedKey: exercise.seedKey.isEmpty ? nil : exercise.seedKey,
                    name: exercise.name,
                    muscleGroups: exercise.muscleGroups,
                    equipmentTypeRaw: exercise.equipmentTypeRaw,
                    loadBehaviorRaw: exercise.loadBehaviorRaw
                )
            }
            .sorted { lhs, rhs in
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                guard nameOrder == .orderedSame else { return nameOrder == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
