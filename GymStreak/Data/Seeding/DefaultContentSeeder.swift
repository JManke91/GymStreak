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
///
/// The version flag and the seeded rows live in different stores (iCloud KV vs.
/// CloudKit), so they can desynchronise — a device can carry "already seeded"
/// while holding no data at all. `recoverStrandedLibraryIfNeeded()` is the way
/// back out of that dead end. See docs/starter-exercise-library.md.
@MainActor
final class DefaultContentSeeder {
    private static let catalogVersionKey = "seedCatalogVersion"

    private let modelContext: ModelContext
    private let cloudSyncStatus: CloudSyncStatusProviding
    private let defaults: UserDefaults
    private let cloudVersionStore: SeedCatalogVersionStore

    init(
        modelContext: ModelContext,
        cloudSyncStatus: CloudSyncStatusProviding,
        defaults: UserDefaults = .standard,
        cloudVersionStore: SeedCatalogVersionStore = UbiquitousSeedCatalogVersionStore()
    ) {
        self.modelContext = modelContext
        self.cloudSyncStatus = cloudSyncStatus
        self.defaults = defaults
        self.cloudVersionStore = cloudVersionStore
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

    /// Recovers a library that the version flag has stranded: the flag says the
    /// catalog was seeded, but this store holds nothing at all.
    ///
    /// The flag travels in `NSUbiquitousKeyValueStore` while the exercises travel
    /// in CloudKit, and the two are not transactional — a reinstall, a store the
    /// user purged from iCloud, or a device whose mirroring never runs leaves the
    /// flag set over an empty store, and `run()` would then refuse to seed for the
    /// lifetime of the install.
    ///
    /// An empty store is not proof of a stranded library on its own: every new
    /// device of an existing user starts empty and fills in from CloudKit moments
    /// later, and seeding into that window would upload 96 rows just to delete
    /// them again on the next dedup pass. So the recovery waits for CloudKit to
    /// declare itself: either it can never deliver (`.off` — signed out, or the
    /// local-only store fallback), or a transfer has completed and the store is
    /// *still* empty. Anything the sync brings down cancels the recovery.
    ///
    /// - Returns: `true` when the catalog was actually re-seeded.
    @discardableResult
    func recoverStrandedLibraryIfNeeded() async -> Bool {
        // A library the normal seed pass can still fill needs no recovery.
        guard storedCatalogVersion >= SeedExerciseCatalog.currentVersion else { return false }

        for await status in cloudSyncStatus.statusUpdates() {
            guard isStoreEmpty else { return false }
            switch status.state {
            case .off:
                return seedStrandedLibrary()
            case .upToDate, .syncing, .waiting:
                // `lastSuccessfulSync` is nil until a transfer has finished, which
                // is exactly the window in which an empty store means nothing yet.
                guard status.lastSuccessfulSync != nil else { continue }
                return seedStrandedLibrary()
            }
        }
        return false
    }

    private func seedStrandedLibrary() -> Bool {
        do {
            seedIfNeeded(existing: [], ignoringStoredVersion: true)
            guard modelContext.hasChanges else { return false }
            try modelContext.save()
            // Unlike `run()`, this lands seconds into the session, after the
            // view models have already read an empty library. The store-changed
            // notification is what makes them refetch — and it carries the new
            // catalog to the watch through ExerciseCatalogSyncCoordinator.
            NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
            return true
        } catch {
            print("DefaultContentSeeder recovery failed: \(error)")
            return false
        }
    }

    /// No exercises, no routines, no history — nothing has ever reached this
    /// store. Deliberately stricter than "no seeded exercises": a user who
    /// deleted the built-ins but kept their own content must not get them back.
    /// A failed count reads as non-empty, so an error never triggers seeding.
    private var isStoreEmpty: Bool {
        isEmpty(FetchDescriptor<Exercise>())
            && isEmpty(FetchDescriptor<Routine>())
            && isEmpty(FetchDescriptor<WorkoutSession>())
    }

    private func isEmpty<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Bool {
        ((try? modelContext.fetchCount(descriptor)) ?? 1) == 0
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

    /// - Parameter ignoringStoredVersion: set by the stranded-library recovery,
    ///   which has established that the flag is lying about this store and starts
    ///   the version scope over from zero so every catalog row is inserted.
    private func seedIfNeeded(existing: [Exercise], ignoringStoredVersion: Bool = false) {
        let lastSeededVersion = ignoringStoredVersion ? 0 : storedCatalogVersion
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
        max(
            cloudVersionStore.version(forKey: Self.catalogVersionKey),
            defaults.integer(forKey: Self.catalogVersionKey)
        )
    }

    private func storeCatalogVersion(_ version: Int) {
        cloudVersionStore.setVersion(version, forKey: Self.catalogVersionKey)
        defaults.set(version, forKey: Self.catalogVersionKey)
    }
}

/// The cross-device half of the catalog version flag.
///
/// Behind a protocol because `NSUbiquitousKeyValueStore` has exactly one usable
/// instance (`.default`) whose contents live outside the app container and
/// survive deleting the app — a test that wrote it would stamp the developer's
/// simulator for good, and a test that read it would inherit whatever that
/// simulator already carries.
protocol SeedCatalogVersionStore: Sendable {
    func version(forKey key: String) -> Int
    func setVersion(_ version: Int, forKey key: String)
}

/// Production implementation: iCloud key-value storage, so a device the user
/// already seeded on does not seed again.
struct UbiquitousSeedCatalogVersionStore: SeedCatalogVersionStore {
    func version(forKey key: String) -> Int {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        return Int(store.longLong(forKey: key))
    }

    func setVersion(_ version: Int, forKey key: String) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(Int64(version), forKey: key)
        store.synchronize()
    }
}
