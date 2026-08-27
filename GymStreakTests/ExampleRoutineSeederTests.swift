//
//  ExampleRoutineSeederTests.swift
//  GymStreakTests
//
//  Covers the built-in example routine: who gets it, who never does, and what
//  happens when two devices seed it before they sync.
//
//  The stored version reads `max(iCloud KV, defaults)` and both halves are
//  injected here — the real `NSUbiquitousKeyValueStore` is a single
//  process-wide instance whose contents outlive the app, so a test that wrote
//  it would stamp the developer's simulator permanently.
//

import Testing
import SwiftData
import Foundation
@testable import GymStreak

/// Counts notification posts from a `@Sendable` observer block. A captured
/// `var` would compile with a Swift 6 concurrency warning, and the project ships
/// warning-free.
private final class PostCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// Stands in for iCloud key-value storage, which tests must never touch.
private final class InMemoryRoutineVersionStore: SeedCatalogVersionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [String: Int]

    init(_ versions: [String: Int] = [:]) {
        self.versions = versions
    }

    func version(forKey key: String) -> Int {
        lock.withLock { versions[key] ?? 0 }
    }

    func setVersion(_ version: Int, forKey key: String) {
        lock.withLock { versions[key] = version }
    }
}

// Serialized for the same reason as the other SwiftData suites: concurrent
// in-memory container creation is not safe within one process.
@Suite(.serialized)
@MainActor
struct ExampleRoutineSeederTests {

    private static let row = SeedRoutineCatalog.entries[0]

    // MARK: - Fixtures

    private struct Fixture {
        let context: ModelContext
        let seeder: ExampleRoutineSeeder
        let versionStore: InMemoryRoutineVersionStore
        let defaults: UserDefaults
    }

    /// - Parameter exerciseSeedKeys: which of the routine's exercises exist in
    ///   the library. Defaults to all of them.
    private func makeFixture(
        exerciseSeedKeys: [String]? = nil,
        storedVersion: Int? = nil,
        context existing: ModelContext? = nil,
        versionStore existingStore: InMemoryRoutineVersionStore? = nil,
        defaults existingDefaults: UserDefaults? = nil
    ) -> Fixture {
        let context = existing ?? ModelContext(InMemoryModelContainer.make())
        let defaults = existingDefaults
            ?? UserDefaults(suiteName: "ExampleRoutineSeederTests.\(UUID().uuidString)")!
        let versionStore = existingStore ?? InMemoryRoutineVersionStore()
        if let storedVersion {
            versionStore.setVersion(storedVersion, forKey: "seedRoutineVersion")
        }

        if existing == nil {
            let keys = exerciseSeedKeys ?? Self.row.exercises.map(\.exerciseSeedKey)
            for key in keys {
                let exercise = Exercise(name: key.localized)
                exercise.seedKey = key
                context.insert(exercise)
            }
            try? context.save()
        }

        return Fixture(
            context: context,
            seeder: ExampleRoutineSeeder(
                modelContext: context,
                defaults: defaults,
                cloudVersionStore: versionStore
            ),
            versionStore: versionStore,
            defaults: defaults
        )
    }

    private func routines(_ context: ModelContext) throws -> [Routine] {
        try context.fetch(FetchDescriptor<Routine>())
    }

    // MARK: - Seeding

    @Test
    func seedsTheExampleRoutineIntoAStoreWithNoRoutines() throws {
        let fixture = makeFixture()

        fixture.seeder.run()

        let seeded = try #require(try routines(fixture.context).first)
        #expect(try routines(fixture.context).count == 1)
        #expect(seeded.seedKey == Self.row.seedKey)
        #expect(seeded.routineExercisesList.count == Self.row.exercises.count)

        for (index, slot) in Self.row.exercises.enumerated() {
            let routineExercise = try #require(
                seeded.routineExercisesList.first { $0.order == index }
            )
            #expect(routineExercise.exercise?.seedKey == slot.exerciseSeedKey)
            #expect(routineExercise.targetRepMin == slot.targetRepMin)
            #expect(routineExercise.targetRepMax == slot.targetRepMax)
            #expect(routineExercise.setsList.count == slot.setCount)
            #expect(routineExercise.setsList.allSatisfy { $0.reps == slot.reps })
            #expect(routineExercise.setsList.allSatisfy { $0.restTime == slot.restTime })
            // A fake starting load would poison the user's first progress chart.
            #expect(routineExercise.setsList.allSatisfy { $0.weight == 0 })
        }

        // No plan: a schedule the user never chose would start driving weekly
        // goals and planning nudges on day one.
        #expect(seeded.schedule == nil)
    }

    @Test
    func seedsTheCurlPushdownPairAsOneSuperset() throws {
        let fixture = makeFixture()

        fixture.seeder.run()

        let seeded = try #require(try routines(fixture.context).first)
        let supersetMembers = seeded.routineExercisesList
            .filter { $0.supersetId != nil }
            .sorted { $0.supersetOrder < $1.supersetOrder }

        #expect(supersetMembers.count == 2)
        #expect(Set(supersetMembers.map(\.supersetId)).count == 1)
        #expect(supersetMembers.map { $0.exercise?.seedKey } == [
            "seed.exercise.dumbbell_curl",
            "seed.exercise.tricep_pushdown"
        ])
        #expect(supersetMembers.map(\.supersetOrder) == [0, 1])
    }

    /// The name must come out of the strings table, not a literal — the seeded
    /// routine is a German user's routine too.
    @Test
    func namesTheRoutineFromTheStringsTable() throws {
        let fixture = makeFixture()

        fixture.seeder.run()

        let seeded = try #require(try routines(fixture.context).first)
        #expect(seeded.name == Self.row.seedKey.localized)
        #expect(seeded.name != Self.row.seedKey)
    }

    /// `RoutinesView` is the first tab, so its view model has already fetched an
    /// empty list by the time the launch `.onAppear` runs the seeder. Without
    /// this notification the user meets the empty state and only finds the
    /// routine after relaunching.
    @Test
    func announcesTheSeededRoutineSoTheAlreadyLoadedListRefetches() throws {
        let fixture = makeFixture()
        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: nil
        ) { _ in posts.record() }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.seeder.run()
        #expect(posts.value == 1)

        // A launch that seeds nothing must stay silent — every listener refetches
        // and re-syncs the watch on this.
        fixture.seeder.run()
        #expect(posts.value == 1)
    }

    @Test
    func doesNotSeedIntoAStoreThatAlreadyHasRoutines() throws {
        let fixture = makeFixture()
        fixture.context.insert(Routine(name: "My Own Routine"))
        try fixture.context.save()

        fixture.seeder.run()

        let all = try routines(fixture.context)
        #expect(all.count == 1)
        #expect(all[0].seedKey.isEmpty)
    }

    // MARK: - Never resurrect

    @Test
    func doesNotBringTheRoutineBackAfterTheUserDeletesIt() throws {
        let fixture = makeFixture()
        fixture.seeder.run()
        let seeded = try #require(try routines(fixture.context).first)
        fixture.context.delete(seeded)
        try fixture.context.save()

        fixture.seeder.run()

        #expect(try routines(fixture.context).isEmpty)
    }

    /// The version flag travels in iCloud KV, so the user's *second* device
    /// must not re-seed either — even though its own routine list is empty.
    @Test
    func doesNotSeedOnASecondDeviceThatInheritedTheVersionFlag() throws {
        let fixture = makeFixture(storedVersion: SeedRoutineCatalog.currentVersion)

        fixture.seeder.run()

        #expect(try routines(fixture.context).isEmpty)
    }

    // MARK: - Deduplication

    @Test
    func collapsesTwoSeededCopiesIntoTheOlderOne() throws {
        let fixture = makeFixture()
        let older = Routine(name: "Full Body Starter")
        older.seedKey = Self.row.seedKey
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = Routine(name: "Full Body Starter")
        newer.seedKey = Self.row.seedKey
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        let strayExercise = RoutineExercise(order: 0)
        strayExercise.routine = newer
        newer.routineExercises?.append(strayExercise)
        fixture.context.insert(older)
        fixture.context.insert(newer)
        try fixture.context.save()

        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: nil
        ) { _ in posts.record() }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.seeder.run()

        let all = try routines(fixture.context)
        #expect(all.count == 1)
        #expect(all.first?.id == older.id)
        // The loser's exercises go with it — nothing left dangling.
        #expect(try fixture.context.fetchCount(FetchDescriptor<RoutineExercise>()) == 0)
        // A collapsed duplicate is a change to the list like any other, and the
        // already-loaded view has to hear about it.
        #expect(posts.value == 1)
    }

    /// Both devices run the same sort, so they keep the same record. A dedup
    /// that picked locally would let two devices delete each other's copy.
    @Test
    func picksTheSameSurvivorRegardlessOfFetchOrder() throws {
        let sameInstant = Date(timeIntervalSince1970: 3_000)

        for reversed in [false, true] {
            let fixture = makeFixture()
            var copies = (0..<2).map { _ -> Routine in
                let routine = Routine(name: "Full Body Starter")
                routine.seedKey = Self.row.seedKey
                routine.createdAt = sameInstant
                return routine
            }
            copies.sort { $0.id.uuidString < $1.id.uuidString }
            for routine in (reversed ? copies.reversed() : copies) {
                fixture.context.insert(routine)
            }
            try fixture.context.save()

            fixture.seeder.run()

            // Same `createdAt`, so the tie-break decides: the smallest id wins,
            // whichever order the fetch happened to hand them over in.
            let survivor = try #require(try routines(fixture.context).first)
            #expect(survivor.id == copies[0].id)
        }
    }

    @Test
    func keepsHistoryAndPlanWhenCollapsingDuplicates() throws {
        let fixture = makeFixture()
        let older = Routine(name: "Full Body Starter")
        older.seedKey = Self.row.seedKey
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = Routine(name: "Full Body Starter")
        newer.seedKey = Self.row.seedKey
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        fixture.context.insert(older)
        fixture.context.insert(newer)

        let session = WorkoutSession(routine: newer)
        fixture.context.insert(session)
        let schedule = RoutineSchedule()
        schedule.routine = newer
        fixture.context.insert(schedule)
        try fixture.context.save()

        fixture.seeder.run()

        #expect(session.routine?.id == older.id)
        #expect(older.schedule?.id == schedule.id)
    }

    // MARK: - Superseded example (seeded into a store CloudKit had not filled)

    /// The first launch of a new device of an existing user: the routine list is
    /// empty because mirroring has not started and the version flag has not
    /// downloaded, so the seeder does its job on false information. `deduplicate`
    /// cannot fix it — the user's real routines carry no `seedKey` — so the next
    /// launch removes it instead.
    @Test
    func removesAnExampleRoutineThatCloudKitLaterProvedWasNotWanted() throws {
        let fixture = makeFixture()
        fixture.seeder.run()
        let seeded = try #require(try routines(fixture.context).first)

        // CloudKit lands the user's real routines, created long before.
        let imported = Routine(name: "Push Day")
        imported.createdAt = seeded.createdAt.addingTimeInterval(-90 * 24 * 3600)
        imported.updatedAt = imported.createdAt
        fixture.context.insert(imported)
        try fixture.context.save()

        fixture.seeder.run()

        let all = try routines(fixture.context)
        #expect(all.count == 1)
        #expect(all.first?.id == imported.id)
    }

    /// The removal has to announce itself for the same reason the seed does —
    /// otherwise the already-loaded list keeps showing a routine that no longer
    /// exists, and the watch keeps its copy.
    @Test
    func announcesTheRemovalOfASupersededExampleRoutine() throws {
        let fixture = makeFixture()
        fixture.seeder.run()
        let seeded = try #require(try routines(fixture.context).first)

        let imported = Routine(name: "Push Day")
        imported.createdAt = seeded.createdAt.addingTimeInterval(-90 * 24 * 3600)
        imported.updatedAt = imported.createdAt
        fixture.context.insert(imported)
        try fixture.context.save()

        let posts = PostCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: nil
        ) { _ in posts.record() }
        defer { NotificationCenter.default.removeObserver(observer) }

        fixture.seeder.run()
        #expect(posts.value == 1)

        // Nothing left to remove — and nothing to say.
        fixture.seeder.run()
        #expect(posts.value == 1)
    }

    /// Routines the user creates *after* meeting the example routine are the
    /// normal case, and must never trigger the cleanup.
    @Test
    func keepsTheExampleRoutineWhenTheUsersOwnRoutinesCameLater() throws {
        let fixture = makeFixture()
        fixture.seeder.run()
        let seeded = try #require(try routines(fixture.context).first)

        let own = Routine(name: "Leg Day")
        own.createdAt = seeded.createdAt.addingTimeInterval(3600)
        fixture.context.insert(own)
        try fixture.context.save()

        fixture.seeder.run()

        #expect(try routines(fixture.context).count == 2)
    }

    /// An example routine the user has trained or edited is theirs now, whatever
    /// arrived afterwards.
    @Test
    func keepsASupersededExampleRoutineTheUserHasAlreadyUsed() throws {
        for makeItTouched in [
            { (routine: Routine, context: ModelContext) in
                routine.updatedAt = routine.createdAt.addingTimeInterval(60)
            },
            { (routine: Routine, context: ModelContext) in
                context.insert(WorkoutSession(routine: routine))
            }
        ] {
            let fixture = makeFixture()
            fixture.seeder.run()
            let seeded = try #require(try routines(fixture.context).first)
            makeItTouched(seeded, fixture.context)

            let imported = Routine(name: "Push Day")
            imported.createdAt = seeded.createdAt.addingTimeInterval(-90 * 24 * 3600)
            imported.updatedAt = imported.createdAt
            fixture.context.insert(imported)
            try fixture.context.save()

            fixture.seeder.run()

            #expect(try routines(fixture.context).count == 2)
        }
    }

    /// The ordering hazard the cleanup and dedup passes create together: the
    /// user trained the *duplicate* copy, and `deduplicate` re-points those
    /// sessions onto the survivor. If the cleanup judged the survivor after that
    /// reassignment, it would read an untouched routine and delete a trained one,
    /// orphaning the history dedup had just rescued.
    @Test
    func keepsATrainedExampleRoutineWhenTheTrainingLandedOnTheOtherCopy() throws {
        let fixture = makeFixture()
        let older = Routine(name: "Full Body Starter")
        older.seedKey = Self.row.seedKey
        older.createdAt = Date(timeIntervalSince1970: 5_000)
        older.updatedAt = older.createdAt
        let newer = Routine(name: "Full Body Starter")
        newer.seedKey = Self.row.seedKey
        newer.createdAt = Date(timeIntervalSince1970: 6_000)
        newer.updatedAt = newer.createdAt
        fixture.context.insert(older)
        fixture.context.insert(newer)

        // Trained on the copy that will lose the dedup.
        let session = WorkoutSession(routine: newer)
        fixture.context.insert(session)

        // And an older user routine, so the cleanup pass is armed.
        let imported = Routine(name: "Push Day")
        imported.createdAt = Date(timeIntervalSince1970: 1_000)
        imported.updatedAt = imported.createdAt
        fixture.context.insert(imported)
        try fixture.context.save()

        fixture.seeder.run()

        let all = try routines(fixture.context)
        #expect(all.count == 2)
        #expect(all.contains { $0.id == older.id })
        // The history survived and still points at a routine.
        #expect(session.routine?.id == older.id)
    }

    // MARK: - Missing exercises

    @Test
    func dropsSlotsWhoseExerciseTheUserDeleted() throws {
        // Five of six present: the plank is gone.
        let fixture = makeFixture(
            exerciseSeedKeys: Self.row.exercises
                .map(\.exerciseSeedKey)
                .filter { $0 != "seed.exercise.plank" }
        )

        fixture.seeder.run()

        let seeded = try #require(try routines(fixture.context).first)
        #expect(seeded.routineExercisesList.count == 5)
        #expect(!seeded.routineExercisesList.contains { $0.exercise?.seedKey == "seed.exercise.plank" })
        // The gap the plank left is closed, not left as a hole.
        #expect(Set(seeded.routineExercisesList.map(\.order)) == Set(0..<5))
        // Nothing was resurrected to fill it.
        #expect(try fixture.context.fetchCount(FetchDescriptor<Exercise>()) == 5)
    }

    /// A superset needs two partners. With one gone the survivor is a plain
    /// exercise, not a one-member superset.
    @Test
    func collapsesASupersetThatLostAPartner() throws {
        let fixture = makeFixture(
            exerciseSeedKeys: Self.row.exercises
                .map(\.exerciseSeedKey)
                .filter { $0 != "seed.exercise.tricep_pushdown" }
        )

        fixture.seeder.run()

        let seeded = try #require(try routines(fixture.context).first)
        #expect(seeded.routineExercisesList.allSatisfy { $0.supersetId == nil })
    }

    /// A two-exercise stump is a worse first impression than the empty state,
    /// and — crucially — the version stays unstamped so a library that arrives
    /// later still gets the routine.
    @Test
    func defersRatherThanSeedingAStumpAndRetriesOnceTheLibraryIsThere() throws {
        let fixture = makeFixture(exerciseSeedKeys: ["seed.exercise.barbell_back_squat"])

        fixture.seeder.run()

        #expect(try routines(fixture.context).isEmpty)
        #expect(fixture.versionStore.version(forKey: "seedRoutineVersion") == 0)

        // The library shows up (a stranded store recovered, or CloudKit landed).
        for key in Self.row.exercises.map(\.exerciseSeedKey).dropFirst() {
            let exercise = Exercise(name: key.localized)
            exercise.seedKey = key
            fixture.context.insert(exercise)
        }
        try fixture.context.save()

        let second = makeFixture(
            context: fixture.context,
            versionStore: fixture.versionStore,
            defaults: fixture.defaults
        )
        second.seeder.run()

        let seeded = try #require(try routines(fixture.context).first)
        #expect(seeded.routineExercisesList.count == Self.row.exercises.count)
    }
}
