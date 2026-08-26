//
//  InMemoryModelContainer.swift
//  GymStreakTests
//
//  Builds an in-memory SwiftData ModelContainer over the full app schema, so
//  repository/view-model tests exercise real SwiftData behavior (predicates,
//  cascade rules, sorting) without touching disk or CloudKit.
//
//  The type list comes from `GymStreakSchema.modelTypes` — the single source of
//  truth shared with the app's own ModelContainer — never a hand-copied list.
//  This file used to hand-copy one, and it silently drifted: it omitted
//  `RoutineSchedule` for over a month. `SchemaRegistrationTests` now fails if a
//  new @Model type escapes the shared list.
//
//  `cloudKitDatabase` must be explicit here: the in-memory `ModelConfiguration`
//  initializer defaults it to `.automatic`, which makes SwiftData run CloudKit's
//  schema validation and container setup on a store that can never sync. `.none`
//  opts these purely local containers out of that entirely. (Historically this was
//  load-bearing for a second reason — the schema itself failed that validation
//  while `RoutineExerciseAlternative.exercise` had no declared inverse, which made
//  container creation fail intermittently. That inverse exists now; keep `.none`
//  for the first reason. See docs/unit-testing.md §2.)
//

import Foundation
import SwiftData
@testable import GymStreak

enum InMemoryModelContainer {
    @MainActor
    static func make() -> ModelContainer {
        let schema = Schema(GymStreakSchema.modelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}
