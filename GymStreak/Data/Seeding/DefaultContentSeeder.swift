import Foundation
import SwiftData

/// What the stranded-library recovery waits on: the sync status, plus the
/// one-shot expiry of its settle window.
///
/// File scope rather than nested in `DefaultContentSeeder`: a type nested in a
/// `@MainActor` class inherits that isolation, and the settle-window timer
/// yields these from a task that is deliberately not on the main actor.
private enum StrandedLibraryRecoveryEvent: Sendable {
    case status(CloudSyncStatus)
    case settleWindowElapsed
}

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
    private let settleWindow: Duration
    private let importBurstGrace: Duration
    /// `deduplicate` deletes duplicate `Exercise` rows, and the History model actor
    /// fetches the **whole** `Exercise` table. This runs at launch, when a rebuild can
    /// already be in flight. See `HistoryStoreGate` and `docs/history-delete-race.md`.
    /// (`recoverStrandedLibraryIfNeeded` needs no gate — it only inserts.)
    private let historyStoreGate: HistoryStoreGate

    /// - Parameters:
    ///   - settleWindow: how long the stranded-library recovery gives CloudKit
    ///     to report *anything* before it stops waiting for proof.
    ///   - importBurstGrace: how long it waits after an import reports success
    ///     before acting on it, so a burst of import events finishes first.
    ///
    /// Both are guesses, both are deliberately backstops rather than the gate,
    /// and both are sized from community measurement rather than anything Apple
    /// publishes — see `recoverStrandedLibraryIfNeeded()` for the numbers and
    /// their sourcing.
    init(
        modelContext: ModelContext,
        cloudSyncStatus: CloudSyncStatusProviding,
        defaults: UserDefaults = .standard,
        cloudVersionStore: SeedCatalogVersionStore = UbiquitousSeedCatalogVersionStore(),
        settleWindow: Duration = .seconds(45),
        importBurstGrace: Duration = .seconds(3),
        historyStoreGate: HistoryStoreGate
    ) {
        self.modelContext = modelContext
        self.cloudSyncStatus = cloudSyncStatus
        self.defaults = defaults
        self.cloudVersionStore = cloudVersionStore
        self.settleWindow = settleWindow
        self.importBurstGrace = importBurstGrace
        self.historyStoreGate = historyStoreGate
    }

    /// `async` because `deduplicate` deletes `Exercise` rows the History model actor
    /// may be holding — see `historyStoreGate`. The whole pass is bracketed so its
    /// fetch, dedup and save see a consistent store.
    func run() async {
        await historyStoreGate.withAccess { runLocked() }
    }

    private func runLocked() {
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
    /// declare itself before reading an empty store as stranded. Anything the
    /// sync brings down meanwhile cancels the recovery.
    ///
    /// **The two failure modes are asymmetric, and that decides the gate.**
    /// Seeding too eagerly produces a duplicate catalog, which the next launch's
    /// `deduplicate()` pass collapses deterministically (imported originals win
    /// on `createdAt`) — ugly for one session, self-healing. Seeding too
    /// conservatively leaves an empty library with no way out from inside the
    /// app, which is the bug this exists to fix. So it biases towards seeding,
    /// but never before mirroring has had a real chance:
    ///
    /// - `.off` / `.failing` — nothing will ever arrive (signed out, the
    ///   local-only store fallback, an export CloudKit keeps rejecting). Seed at
    ///   once.
    /// - `.syncing` — a transfer is genuinely in flight; this is the new device
    ///   of an existing user, mid-import. Never seed, however long it takes.
    /// - `.upToDate` / `.waiting` — seed once **either** an import has completed
    ///   in this session (`hasCompletedImportThisSession`, the real signal:
    ///   mirroring delivered and the store is still empty) **or** the settle
    ///   window has elapsed without CloudKit reporting anything at all.
    ///
    /// The two durations are the only guesses here, and both are deliberately
    /// backstops rather than the gate. Neither is an Apple-published figure —
    /// Apple documents no mirroring latency at all — so they are sized from the
    /// consistently-reported community measurement that **mirroring does not
    /// begin until roughly 20–30 s after launch** on a healthy device:
    ///
    /// - `settleWindow` (45 s) has to sit well clear of that start latency. A
    ///   shorter window is not a smaller compromise, it is the reverted
    ///   `.upToDate` bug on a delay: it expires while a perfectly healthy device
    ///   of an existing user has simply not posted its first event yet, and the
    ///   status at that moment is the same optimistic cold-launch `.upToDate`.
    ///   The window covers the device where no event *ever* arrives — mirroring
    ///   never set up, or offline, where `makeState()` pins `.waiting` and
    ///   quiescence never comes. Recovering an offline device is the asymmetry
    ///   argument applied literally: it gets a usable library now, and a later
    ///   import merges through the same dedup pass.
    /// - `importBurstGrace` (3 s) covers the one way the real signal can lie.
    ///   Import events arrive in **bursts** — several consecutive `.import`
    ///   events within a few seconds — and whether an early batch can complete
    ///   successfully having applied nothing while data-bearing batches are
    ///   still pending is undocumented. So the flag is not acted on the instant
    ///   it flips: wait, then re-read the live state and the store.
    ///
    /// The whole cost of both is one launch's delay on a device that is about to
    /// be re-seeded anyway; on every later launch `run()` handles the library
    /// and nothing waits.
    ///
    /// Two gates that look right and are not, both tried and reverted — see
    /// docs/starter-exercise-library.md:
    /// - `lastSuccessfulSync != nil` is restored from `UserDefaults`, so it
    ///   describes a past session of this install: never true on the stranded
    ///   device that has never synced, already true mid-import on one whose
    ///   defaults outlived its store.
    /// - Bare `state == .upToDate` is optimistic at cold launch — with no events
    ///   opened yet it is the *first* status of every session, so the recovery
    ///   would seed on iteration one, straight into an existing user's import.
    ///
    /// - Returns: `true` when the catalog was actually re-seeded.
    @discardableResult
    func recoverStrandedLibraryIfNeeded() async -> Bool {
        // A library the normal seed pass can still fill needs no recovery.
        guard storedCatalogVersion >= SeedExerciseCatalog.currentVersion else { return false }

        var latest = cloudSyncStatus.currentStatus
        var hasSettled = false

        for await event in recoveryEvents() {
            switch event {
            case .status(let status): latest = status
            case .settleWindowElapsed: hasSettled = true
            }

            // Whatever the sync delivered makes this a normal store, not a
            // stranded one.
            guard isStoreEmpty else { return false }

            switch latest.state {
            case .off, .failing:
                return seedStrandedLibrary()
            case .syncing:
                // An in-flight transfer outranks the settle window: waiting
                // longer costs a session, seeding here costs a duplicate upload.
                continue
            case .upToDate, .waiting:
                guard latest.hasCompletedImportThisSession || hasSettled else { continue }
                // Let a burst of import events finish before believing this one,
                // then decide on live state rather than the event that woke us.
                // A cancelled sleep must not fall through: `try?` alone would
                // seed and post `.cloudKitDataDidChange` after the owning
                // `.task` was already torn down.
                guard (try? await Task.sleep(for: importBurstGrace)) != nil else { return false }
                guard isStoreEmpty else { return false }
                // A follow-up batch opened while we waited: back to waiting.
                guard cloudSyncStatus.currentStatus.state != .syncing else { continue }
                return seedStrandedLibrary()
            }
        }
        return false
    }

    /// The sync-status stream merged with a one-shot settle-window timer.
    ///
    /// Ends only once **both** sources are exhausted, so a status stream that
    /// finishes early cannot cancel the backstop. In production the monitor's
    /// stream never ends, so this is really about keeping the two independent:
    /// the recovery decides on whichever arrives first.
    private func recoveryEvents() -> AsyncStream<StrandedLibraryRecoveryEvent> {
        // Subscribed here, on the main actor, so the merging task captures only
        // `Sendable` values — an `AsyncStream` of a `Sendable` element and a
        // `Duration`. Reaching for `cloudSyncStatus` from inside the task group
        // instead makes the region-based isolation checker give up outright
        // ("pattern that the region-based isolation checker does not understand
        // how to check"), which is a compile error, not a warning.
        let statuses = cloudSyncStatus.statusUpdates()
        let settleWindow = self.settleWindow
        return AsyncStream { continuation in
            let producer = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await status in statuses {
                            continuation.yield(.status(status))
                        }
                    }
                    group.addTask {
                        try? await Task.sleep(for: settleWindow)
                        continuation.yield(.settleWindowElapsed)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
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
