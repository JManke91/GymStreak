import Foundation
import SwiftData

/// Seeds the built-in starter exercise catalog (SeedExerciseCatalog) and keeps
/// it duplicate-free across the user's devices.
///
/// CloudKit-backed SwiftData cannot enforce unique constraints, so two devices
/// seeding independently can both upload the catalog. Protection is layered:
/// 1. A dedup pass runs on every launch and deterministically collapses
///    exercises sharing a `seedKey` — every device picks the same survivor,
///    so concurrent dedup passes never delete both copies.
/// 2. The seed pass is gated by the catalog version in
///    NSUbiquitousKeyValueStore (propagates across the user's devices), with a
///    UserDefaults mirror for accounts without iCloud.
/// 3. Catalog rows whose name matches an exercise the user already created are
///    skipped, so backfilling existing libraries doesn't produce lookalikes.
/// See docs/starter-exercise-library.md.
@MainActor
final class DefaultContentSeeder {
    private static let catalogVersionKey = "seedCatalogVersion"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func run() {
        do {
            let exercises = try modelContext.fetch(FetchDescriptor<Exercise>())
            let survivors = deduplicate(exercises)
            reconcileSeedMetadata(in: survivors)
            seedIfNeeded(existing: survivors)
            reconcileRecordedLoadBehavior(using: survivors)
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            print("DefaultContentSeeder failed: \(error)")
        }
    }

    /// Collapses duplicate seeded exercises (same non-empty `seedKey`) into one
    /// survivor, re-pointing routine references before deleting the copies.
    /// The survivor choice (createdAt, then id) is deterministic so every
    /// device keeps the same record. Returns the surviving exercises.
    private func deduplicate(_ exercises: [Exercise]) -> [Exercise] {
        var survivors = exercises.filter { $0.seedKey.isEmpty }
        let seeded = Dictionary(grouping: exercises.filter { !$0.seedKey.isEmpty }, by: \.seedKey)

        for (_, copies) in seeded {
            let ranked = copies.sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            guard let survivor = ranked.first else { continue }
            survivors.append(survivor)

            for duplicate in ranked.dropFirst() {
                for routineExercise in duplicate.routineExercises ?? [] {
                    routineExercise.exercise = survivor
                }
                for alternative in duplicate.alternativeUses ?? [] {
                    alternative.exercise = survivor
                }
                modelContext.delete(duplicate)
            }
        }
        return survivors
    }

    private func seedIfNeeded(existing: [Exercise]) {
        let lastSeededVersion = storedCatalogVersion
        guard lastSeededVersion < SeedExerciseCatalog.currentVersion else { return }

        let existingSeedKeys = Set(existing.map(\.seedKey))
        let existingNames = Set(existing.map { Self.normalizedName($0.name) })

        for row in SeedExerciseCatalog.entries {
            // Version-scoped insertion: only rows introduced after the last
            // seeded version, so catalog upgrades never resurrect seeds the
            // user deleted.
            guard row.introducedInVersion > lastSeededVersion,
                  !existingSeedKeys.contains(row.seedKey) else { continue }

            // The localized name is resolved once at seed time (device language)
            // and stays user-editable; `seedKey` remains the stable identity.
            let name = row.seedKey.localized

            // Skip rows the user has effectively created themselves — an
            // existing "bankdrücken" blocks the catalog's "Bankdrücken".
            guard !existingNames.contains(Self.normalizedName(name)) else { continue }

            let exercise = Exercise(
                name: name,
                muscleGroups: row.muscleGroups,
                equipmentType: row.equipmentType,
                loadBehavior: row.loadBehavior
            )
            exercise.seedKey = row.seedKey
            modelContext.insert(exercise)
        }
        storeCatalogVersion(SeedExerciseCatalog.currentVersion)
    }

    /// Seed keys are stable product metadata. Unlike names, their behavior may
    /// be corrected after the catalog has shipped, so reconcile it even when a
    /// device has already reached the current catalog version.
    private func reconcileSeedMetadata(in exercises: [Exercise]) {
        let rowsByKey = Dictionary(uniqueKeysWithValues: SeedExerciseCatalog.entries.map { ($0.seedKey, $0) })
        for exercise in exercises {
            guard let row = rowsByKey[exercise.seedKey] else { continue }
            exercise.loadBehavior = row.loadBehavior
        }
    }

    /// Older completed workouts pre-date `WorkoutExercise.loadBehaviorRaw`.
    /// We can safely repair only rows linked by id to a seeded counterweight
    /// exercise; custom exercises remain unchanged until the user classifies
    /// them in the library.
    private func reconcileRecordedLoadBehavior(using exercises: [Exercise]) {
        let assistanceExerciseIds = Set(
            exercises
                .filter { $0.loadBehavior.isCounterweightAssistance }
                .map(\.id)
        )
        guard !assistanceExerciseIds.isEmpty else { return }
        guard let sessions = try? modelContext.fetch(FetchDescriptor<WorkoutSession>()) else { return }
        for workoutExercise in sessions.flatMap(\.workoutExercisesList) {
            guard let exerciseId = workoutExercise.exerciseId,
                  assistanceExerciseIds.contains(exerciseId) else { continue }
            workoutExercise.loadBehavior = .counterweightAssistance
        }
    }

    /// Case-, diacritic-, and whitespace-insensitive form used to detect that a
    /// user-created exercise already covers a catalog row.
    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // MARK: - Catalog version storage

    private var storedCatalogVersion: Int {
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()
        let cloudVersion = Int(cloudStore.longLong(forKey: Self.catalogVersionKey))
        let localVersion = UserDefaults.standard.integer(forKey: Self.catalogVersionKey)
        return max(cloudVersion, localVersion)
    }

    private func storeCatalogVersion(_ version: Int) {
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(Int64(version), forKey: Self.catalogVersionKey)
        cloudStore.synchronize()
        UserDefaults.standard.set(version, forKey: Self.catalogVersionKey)
    }
}
