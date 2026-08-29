//
//  ExampleRoutineSeeder.swift
//  GymStreak
//
//  Seeds the built-in example routine into a store that holds no routines, and
//  keeps it duplicate-free across the user's devices.
//  See docs/example-starter-routine.md.
//

import Foundation
import SwiftData

/// Puts one ready-made routine in front of a user who has none, so the Routines
/// tab teaches rep ranges, supersets and per-exercise rest instead of showing an
/// empty state. The routine is an ordinary routine: startable, editable,
/// deletable, and synced to the watch through the existing path.
///
/// Two mechanisms, and they answer different questions:
///
/// 1. **The version flag decides whether to ever seed again.** Unlike the
///    exercise catalog — where the flag is only an optimisation on top of a
///    per-`seedKey` presence check — here it is the correctness mechanism: the
///    trigger is an *empty* routine list, so without a stamp a user who deleted
///    the example routine would get it back on the very next launch. It lives in
///    `NSUbiquitousKeyValueStore` (so a second device inherits it) with a
///    `UserDefaults` mirror for accounts without iCloud.
/// 2. **The dedup pass decides which copy survives.** CloudKit-backed SwiftData
///    silently ignores `@Attribute(.unique)`, so two devices that both seed
///    before they sync *will* both upload the routine. Duplicates are collapsed
///    into a deterministic survivor (oldest `createdAt`, then smallest `id`) —
///    the same convention `DefaultContentSeeder` uses — so every device keeps
///    the *same* record and concurrent passes never delete both.
///
/// Runs after `DefaultContentSeeder`, whose exercises it resolves against. A
/// device rescued by the stranded-library recovery therefore gets the example
/// routine on its *following* launch: the recovery lands seconds after this ran
/// and found nothing to resolve against — and finding nothing is deliberately
/// not stamped, so the retry happens.
///
/// Neither mechanism covers the first launch of a **new device of an existing
/// user**, where both the routines and the flag are still in flight — see
/// `removeSupersededExampleRoutines`, which cleans that up on the next launch
/// rather than making every new user wait for a CloudKit signal.
@MainActor
final class ExampleRoutineSeeder {
    private static let routineVersionKey = "seedRoutineVersion"
    /// The user's own loads are unknowable, and a fake starting number would
    /// poison their first progress chart.
    private static let seededWeight = 0.0

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let cloudVersionStore: SeedCatalogVersionStore
    /// Both `removeSupersededExampleRoutines` and `deduplicate` delete whole `Routine`
    /// rows, whose cascade takes their `RoutineExercise` children with them — and the
    /// History model actor holds both (it fetches every `Routine`, and
    /// `fetchLiveRoutineSlotIds` walks `routineExercisesList`). This runs at launch,
    /// when a History rebuild can already be in flight, so it takes the gate like any
    /// other deleter. See `HistoryStoreGate` and `docs/history-delete-race.md`.
    private let historyStoreGate: HistoryStoreGate

    /// - Parameter historyStoreGate: **`AppDependencies`' shared gate.** Deliberately not
    ///   defaulted, like the three Data-layer providers: a writer handed its own gate
    ///   compiles, looks wired and excludes nothing. Tests opt out visibly with
    ///   `HistoryStoreGate.unshared()`.
    init(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        cloudVersionStore: SeedCatalogVersionStore = UbiquitousSeedCatalogVersionStore(),
        historyStoreGate: HistoryStoreGate
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.cloudVersionStore = cloudVersionStore
        self.historyStoreGate = historyStoreGate
    }

    /// `async` because the dedup and cleanup passes below delete `Routine` rows the
    /// History model actor may be walking — see `historyStoreGate`. The whole body is
    /// bracketed rather than just the deletions: it is one launch-time pass whose
    /// fetches, deletes and single save have to see a consistent store.
    func run() async {
        await historyStoreGate.withAccess { runLocked() }
    }

    private func runLocked() {
        do {
            let seededRoutines = try modelContext.fetch(
                FetchDescriptor<Routine>(predicate: #Predicate { $0.seedKey != "" })
            )
            // Dedup runs **first**, and the order is load-bearing in both
            // directions. Dedup must go first because its survivor choice is
            // deterministic — every device keeps the same record — whereas the
            // cleanup's "was this trained?" test is answered from local state
            // that two mid-sync devices can disagree about; cleaning up first
            // would let two devices keep different copies and delete each
            // other's, which is the one dedup failure mode this project's
            // notes call out as unrecoverable.
            //
            // That puts the cleanup downstream of dedup re-pointing a loser's
            // `WorkoutSession`s onto the survivor, so it depends on that
            // reassignment being visible through the inverse array — otherwise
            // it would read an untouched routine and delete a trained one,
            // orphaning the very history dedup rescued (`Routine.workoutSessions`
            // has no delete rule, so those sessions would survive with
            // `routine == nil`). It *is* visible; SwiftData maintains both sides
            // in memory. `keepsATrainedExampleRoutineWhenTheTrainingLandedOnTheOtherCopy`
            // pins it, and is the test to look at if this order is ever changed.
            let (survivors, didCollapseDuplicates) = deduplicate(seededRoutines)
            let kept = removeSupersededExampleRoutines(survivors)
            let didRemoveSuperseded = kept.count < survivors.count
            let didSeed = try seedIfNeeded()
            if modelContext.hasChanges {
                try modelContext.save()
            }
            // `RoutinesView` is the first tab, so its view model is constructed
            // during the first render pass — before the `.onAppear` that runs
            // this. Without the notification a seeded routine would go unseen
            // until the next launch, and a removed or collapsed one would linger
            // on screen after it stopped existing. Also what carries any of the
            // three to the watch, through the ordinary sync path.
            if didSeed || didRemoveSuperseded || didCollapseDuplicates {
                NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
            }
        } catch {
            print("ExampleRoutineSeeder failed: \(error)")
        }
    }

    // MARK: - Seeding

    /// - Returns: `true` when a routine was actually inserted.
    private func seedIfNeeded() throws -> Bool {
        // Cheapest possible early out, and the one every launch after the first
        // takes: a stamped device asks the routine list nothing at all.
        guard storedRoutineVersion < SeedRoutineCatalog.currentVersion else { return false }

        // Counted, not materialized — the Routines tab is the screen this app has
        // already had to rescue from a main-thread hang once
        // (docs/history-performance.md). Deletions staged above can only ever have
        // left a survivor or an older user routine behind, so this cannot read
        // zero on a store that had content.
        // A user who already has routines never gets an example one — and never
        // needs looking at again.
        guard try modelContext.fetchCount(FetchDescriptor<Routine>()) == 0 else {
            storeRoutineVersion(SeedRoutineCatalog.currentVersion)
            return false
        }

        let exercisesBySeedKey = try seededExercisesBySeedKey()
        var didSeed = false
        var didDefer = false
        for row in SeedRoutineCatalog.entries {
            if seed(row, exercisesBySeedKey: exercisesBySeedKey) { didSeed = true } else { didDefer = true }
        }
        // Deferring is not a decision: the library was too thin *this launch*
        // (a stranded store, or one still importing). Leave the version unstamped
        // so a later launch can try again.
        guard !didDefer else { return didSeed }
        storeRoutineVersion(SeedRoutineCatalog.currentVersion)
        return didSeed
    }

    /// - Returns: `false` when too few of the routine's exercises resolve, which
    ///   defers the whole seed rather than producing a stump.
    private func seed(_ row: SeedRoutine, exercisesBySeedKey: [String: Exercise]) -> Bool {
        // Slots whose exercise the user deleted are dropped, never resurrected.
        let resolved = row.exercises.compactMap { slot in
            exercisesBySeedKey[slot.exerciseSeedKey].map { (slot: slot, exercise: $0) }
        }
        guard resolved.count >= row.minimumResolvedExercises else { return false }

        // A superset needs two partners; one survivor is just an exercise.
        var membersPerGroup: [String: Int] = [:]
        for entry in resolved {
            guard let group = entry.slot.supersetGroup else { continue }
            membersPerGroup[group, default: 0] += 1
        }

        // The localized name is resolved once at seed time (device language)
        // into the mutable `name`, exactly as seeded exercises do; `seedKey`
        // stays the stable identity.
        let routine = Routine(name: row.seedKey.localized)
        routine.seedKey = row.seedKey
        // `Routine.init` stamps the two with separate `Date()` calls, which
        // differ by microseconds. Pinning them equal is what lets the cleanup
        // pass below recognise a routine the user has never edited.
        routine.updatedAt = routine.createdAt
        modelContext.insert(routine)

        var supersetIds: [String: UUID] = [:]
        var supersetOrders: [String: Int] = [:]

        for (order, entry) in resolved.enumerated() {
            let routineExercise = RoutineExercise(exercise: entry.exercise, order: order)
            routineExercise.routine = routine
            routineExercise.targetRepMin = entry.slot.targetRepMin
            routineExercise.targetRepMax = entry.slot.targetRepMax

            if let group = entry.slot.supersetGroup, membersPerGroup[group, default: 0] >= 2 {
                let supersetId = supersetIds[group] ?? UUID()
                supersetIds[group] = supersetId
                routineExercise.supersetId = supersetId
                routineExercise.supersetOrder = supersetOrders[group, default: 0]
                supersetOrders[group, default: 0] += 1
            }

            for setOrder in 0..<entry.slot.setCount {
                let set = ExerciseSet(
                    reps: entry.slot.reps,
                    weight: Self.seededWeight,
                    restTime: entry.slot.restTime,
                    order: setOrder
                )
                set.routineExercise = routineExercise
                routineExercise.sets?.append(set)
            }

            routine.routineExercises?.append(routineExercise)
        }
        return true
    }

    private func seededExercisesBySeedKey() throws -> [String: Exercise] {
        let wanted = Set(SeedRoutineCatalog.entries.flatMap { $0.exercises.map(\.exerciseSeedKey) })
        let exercises = try modelContext.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.seedKey != "" })
        )
        // Last writer wins on a duplicated key; `DefaultContentSeeder` has
        // already collapsed those by the time this runs.
        return Dictionary(
            exercises.filter { wanted.contains($0.seedKey) }.map { ($0.seedKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Superseded-example cleanup

    /// Removes an example routine that only exists because this device seeded it
    /// into a store CloudKit had not finished importing yet.
    ///
    /// The one race the version flag cannot close: on the **first launch of a new
    /// device belonging to an existing user**, the routine list is empty because
    /// mirroring has not started (community measurement puts that 20–30 s after
    /// launch), and `NSUbiquitousKeyValueStore.synchronize()` only flushes —
    /// it does not wait for the flag to download. So the seeder can see "no
    /// routines, never seeded" about a user who has ten routines and deleted the
    /// example one months ago, and upload it to all their devices.
    ///
    /// `deduplicate()` cannot undo that: the spurious routine carries a
    /// `seedKey` and the user's real ones do not, so they never group together.
    /// The signal that it happened is unambiguous, though, and arrives on the
    /// next launch — a routine the user created *before* the example routine was
    /// seeded can only have come from a store that was not actually empty.
    ///
    /// Deliberately **not** solved by gating the seed on a CloudKit signal, as
    /// the stranded-library recovery does. The cost balance is inverted here: a
    /// first-launch user would stare at the empty state for the length of the
    /// settle window, which is precisely what this feature exists to remove, and
    /// no such delay is acceptable for onboarding. Cleaning up afterwards keeps
    /// the fast path fast and makes the rare wrong seed self-healing — the
    /// property `docs/starter-exercise-library.md` argues is the one that
    /// matters.
    ///
    /// Only an **untouched** copy is removed — never trained, never edited — so
    /// a user who started using it in the meantime keeps it.
    ///
    /// One case it deliberately cannot catch: an existing user with **zero**
    /// routines of their own. There is no older user routine to compare against,
    /// so a copy seeded mid-import is indistinguishable from a legitimate one and
    /// stays. The effect is benign — they get the example routine they would have
    /// got anyway — except for the user who had deleted it on another device,
    /// who gets it back once.
    ///
    /// - Returns: the routines that were kept.
    private func removeSupersededExampleRoutines(_ seededRoutines: [Routine]) -> [Routine] {
        guard !seededRoutines.isEmpty else { return seededRoutines }

        // `== ""` rather than `.isEmpty`. `String.isEmpty` inside a `#Predicate`
        // compiles, runs, throws nothing — and is **always false**, so this fetch
        // silently returned no user routines and the cleanup never fired.
        // (Measured: over a store holding one routine with an empty `seedKey`,
        // `$0.seedKey.isEmpty` matched 0 and `!$0.seedKey.isEmpty` matched 1.)
        // Caught by `removesAnExampleRoutineThatCloudKitLaterProvedWasNotWanted`.
        var oldestUserRoutine = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.seedKey == "" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        oldestUserRoutine.fetchLimit = 1
        guard let oldest = try? modelContext.fetch(oldestUserRoutine).first else {
            return seededRoutines
        }

        var kept: [Routine] = []
        for routine in seededRoutines {
            let isSuperseded = oldest.createdAt < routine.createdAt
                && routine.updatedAt == routine.createdAt
                && (routine.workoutSessions ?? []).isEmpty
            if isSuperseded {
                modelContext.delete(routine)
            } else {
                kept.append(routine)
            }
        }
        return kept
    }

    // MARK: - Deduplication

    /// Collapses routines sharing a `seedKey` into one deterministic survivor.
    /// History and any plan the user attached are re-pointed first — the copies'
    /// own exercises and sets go with them via the cascade rule, so nothing is
    /// left dangling.
    ///
    /// - Parameter seededRoutines: seeded routines only. User-created ones carry
    ///   no `seedKey` and are never candidates.
    /// - Returns: the surviving routines, and whether a duplicate was deleted.
    private func deduplicate(_ seededRoutines: [Routine]) -> (survivors: [Routine], didDelete: Bool) {
        var survivors: [Routine] = []
        var didDelete = false
        let seeded = Dictionary(grouping: seededRoutines, by: \.seedKey)

        for (_, copies) in seeded {
            let ranked = copies.sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            guard let survivor = ranked.first else { continue }
            survivors.append(survivor)

            for duplicate in ranked.dropFirst() {
                // History must survive: a session pointing at the deleted copy
                // would otherwise lose its routine link entirely.
                for session in duplicate.workoutSessions ?? [] {
                    session.routine = survivor
                }
                // A plan the user set on this device's copy moves across rather
                // than being cascaded away. `Routine.schedule` already picks
                // deterministically if that leaves the survivor holding two.
                for schedule in duplicate.schedules ?? [] {
                    schedule.routine = survivor
                }
                modelContext.delete(duplicate)
                didDelete = true
            }
        }
        return (survivors, didDelete)
    }

    // MARK: - Version storage

    private var storedRoutineVersion: Int {
        max(
            cloudVersionStore.version(forKey: Self.routineVersionKey),
            defaults.integer(forKey: Self.routineVersionKey)
        )
    }

    private func storeRoutineVersion(_ version: Int) {
        cloudVersionStore.setVersion(version, forKey: Self.routineVersionKey)
        defaults.set(version, forKey: Self.routineVersionKey)
    }
}
