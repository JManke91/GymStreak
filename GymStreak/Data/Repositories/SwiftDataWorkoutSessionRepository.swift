//
//  SwiftDataWorkoutSessionRepository.swift
//  GymStreak
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataWorkoutSessionRepository: WorkoutSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        // History cards and aggregations all walk workoutExercises → sets. Without prefetching,
        // every card faults its exercises individually (N+1 against SQLite) — see
        // docs/history-performance.md §2.4. Nested to-many prefetching (…exercises.sets) is not
        // expressible as a key path, so only the first hop is prefetched.
        descriptor.relationshipKeyPathsForPrefetching = [\.workoutExercises]
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching workout history: \(error)")
            return []
        }
    }

    /// Most recent completed-session start date per routine id.
    ///
    /// One `LIMIT 1` fetch per routine rather than one scan of the whole history.
    /// The two collections grow in different directions: a routine library grows
    /// by user curation and stays in the tens (the free tier caps it at
    /// `ProFeatureCaps.freeRoutineLimit`; Pro does not, so this is a shape
    /// argument, not a hard bound), while completed sessions accumulate forever.
    /// Binding the cost to the former is what keeps this off the main actor's
    /// critical path. SwiftData has no `MAX(...) GROUP BY` surface, and the Core
    /// Data escape hatch needs private-API reflection into `ModelContext`, so N
    /// bounded fetches is the sanctioned shape — see docs/history-performance.md
    /// §1.2a for the alternatives that were rejected.
    func lastCompletedStartDates(forRoutineIds routineIds: [UUID]) -> [UUID: Date] {
        var dates: [UUID: Date] = [:]
        for routineId in routineIds {
            var descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.endTime != nil && $0.routine?.id == routineId },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            do {
                // A routine with no completed sessions simply gets no entry.
                guard let session = try modelContext.fetch(descriptor).first else { continue }
                dates[routineId] = session.startTime
            } catch {
                // Logged rather than swallowed: a predicate-translation failure
                // would fail for every routine at once, and the symptom is silent
                // (every card reads "never trained", the hero card goes arbitrary).
                print("Error fetching last completed date for routine \(routineId): \(error)")
            }
        }
        return dates
    }

    func findSession(id: UUID, healthKitWorkoutId: UUID?) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id || (healthKitWorkoutId != nil && session.healthKitWorkoutId == healthKitWorkoutId)
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func insert(_ session: WorkoutSession) {
        modelContext.insert(session)
    }

    func delete(_ session: WorkoutSession) {
        modelContext.delete(session)
    }

    func insert(_ exercise: WorkoutExercise) {
        modelContext.insert(exercise)
    }

    func delete(_ exercise: WorkoutExercise) {
        modelContext.delete(exercise)
    }

    func insert(_ set: WorkoutSet) {
        modelContext.insert(set)
    }

    func delete(_ set: WorkoutSet) {
        modelContext.delete(set)
    }

    func save() throws {
        try modelContext.save()
    }
}
