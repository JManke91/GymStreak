//
//  PreviewModelContainer.swift
//  GymStreak
//
//  In-memory container for SwiftUI previews, built from `GymStreakSchema.modelTypes`
//  so a preview can never be built over a stale subset of the schema. Previews used
//  to hand-copy their own type lists, and both had already drifted — one was missing
//  `RoutineExerciseAlternative` and `AlternativeExerciseSet`, the other four types on
//  top of that — which turns any preview that touches the missing model into a crash
//  that looks like a SwiftData bug.
//
//  Deliberately not `#if DEBUG`-gated: the `#Preview` macro expands in every
//  configuration, so a Debug-only symbol referenced from a preview breaks the
//  Release build.
//

import SwiftData

enum PreviewModelContainer {
    /// `cloudKitDatabase: .none` is required, not cosmetic: an in-memory
    /// `ModelConfiguration` otherwise defaults to `.automatic` and runs CloudKit's
    /// schema validation and container setup on a store that can never sync. Same
    /// reason `InMemoryModelContainer` in the test target passes it.
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema(GymStreakSchema.modelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }()
}
