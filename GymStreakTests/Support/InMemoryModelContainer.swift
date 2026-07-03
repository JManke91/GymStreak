//
//  InMemoryModelContainer.swift
//  GymStreakTests
//
//  Builds an in-memory SwiftData ModelContainer over the full app schema, so
//  repository/view-model tests exercise real SwiftData behavior (predicates,
//  cascade rules, sorting) without touching disk or CloudKit.
//
//  Schema list must be kept in sync with GymStreak/App/GymStreakApp.swift.
//
//  `cloudKitDatabase` must be explicit here: the in-memory `ModelConfiguration`
//  initializer defaults it to `.automatic`, which makes SwiftData validate the
//  schema against CloudKit's stricter rules. That validation genuinely fails
//  for this schema (`RoutineExerciseAlternative.exercise` has no declared
//  inverse), so an implicit `.automatic` container throws
//  `SwiftDataError._Error.loadIssueModelContainer` — surfaced here as tests
//  crashing intermittently depending on whether CloudKit validation happened
//  to run before the failure was hit. Passing `.none` opts these purely local,
//  in-memory test containers out of that validation entirely.
//

import Foundation
import SwiftData
@testable import GymStreak

enum InMemoryModelContainer {
    @MainActor
    static func make() -> ModelContainer {
        let schema = Schema([
            Routine.self,
            Exercise.self,
            RoutineExercise.self,
            ExerciseSet.self,
            RoutineExerciseAlternative.self,
            AlternativeExerciseSet.self,
            WorkoutSession.self,
            WorkoutExercise.self,
            WorkoutSet.self
        ])
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
