import Foundation
import SwiftData

/// Data-layer read boundary for routine state that has already committed in a
/// sibling SwiftData context. Callers receive value DTOs, never models bound to
/// the short-lived read context.
@MainActor
protocol AuthoritativeRoutineSnapshotProviding: AnyObject {
    func fetchSnapshot() throws -> [WatchRoutine]
}

/// Data-layer transport boundary used by the transaction coordinator. The
/// Domain-facing WatchSyncServicing protocol deliberately does not expose wire
/// DTOs or authoritative-generation mechanics.
@MainActor
protocol WatchRoutineSnapshotTransporting: AnyObject {
    func syncRoutineSnapshot(_ routines: [WatchRoutine])
    func stageAuthoritativeRoutineSnapshot(
        _ routines: [WatchRoutine]
    ) -> (epoch: UUID, generation: UInt64)?
}

/// Mirrors a committed value snapshot into the app's long-lived main context
/// for immediate UI convergence. It never saves or rolls back pre-existing
/// dirty work.
@MainActor
protocol MainContextRoutineCacheRefreshing: AnyObject {
    func refreshCache(from routines: [WatchRoutine])
}

@MainActor
final class SwiftDataAuthoritativeRoutineSnapshotProvider: AuthoritativeRoutineSnapshotProviding {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchSnapshot() throws -> [WatchRoutine] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<Routine>(
            sortBy: [SortDescriptor(\Routine.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toWatchRoutine() }
    }
}

@MainActor
final class SwiftDataMainContextRoutineCacheRefresher: MainContextRoutineCacheRefreshing {
    private let context: ModelContext

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    func refreshCache(from routines: [WatchRoutine]) {
        guard !context.hasChanges else {
            print("WatchTemplateTransaction: main-context cache refresh deferred — unsaved work exists")
            return
        }

        let descriptor = FetchDescriptor<Routine>()
        guard let cachedRoutines = try? context.fetch(descriptor) else {
            print("WatchTemplateTransaction: main-context cache refresh failed — routines unavailable")
            return
        }
        for routineSnapshot in routines {
            guard let cachedRoutine = cachedRoutines.first(where: { $0.id == routineSnapshot.id }) else {
                continue
            }

            for exerciseSnapshot in routineSnapshot.exercises {
                guard let cachedExercise = cachedRoutine.routineExercisesList.first(
                    where: { $0.id == exerciseSnapshot.id }
                ) else { continue }
                for setSnapshot in exerciseSnapshot.sets {
                    guard let cachedSet = cachedExercise.setsList.first(
                        where: { $0.id == setSnapshot.id }
                    ) else { continue }
                    cachedSet.reps = setSnapshot.reps
                    cachedSet.weight = setSnapshot.weight
                }

                for alternativeSnapshot in exerciseSnapshot.alternatives ?? [] {
                    guard let cachedAlternative = cachedExercise.alternativesList.first(
                        where: { $0.id == alternativeSnapshot.id }
                    ) else { continue }
                    for setSnapshot in alternativeSnapshot.sets {
                        guard let cachedSet = cachedAlternative.setsList.first(
                            where: { $0.id == setSnapshot.id }
                        ) else { continue }
                        cachedSet.reps = setSnapshot.reps
                        cachedSet.weight = setSnapshot.weight
                    }
                }
            }
        }

        // The authoritative transaction already committed these exact values.
        // Saving here only establishes them as this context's new baseline so
        // consecutive Watch transactions can refresh again. The clean-context
        // guard above ensures unrelated work is never included.
        do {
            if context.hasChanges { try context.save() }
        } catch {
            print("WatchTemplateTransaction: main-context cache save failed — \(error.localizedDescription)")
            // The context was proven clean at entry and this synchronous
            // MainActor method introduced every pending change. Discard only
            // those failed mirror mutations so they cannot overwrite a newer
            // authoritative sibling-context commit in some later save.
            context.rollback()
        }
    }
}
