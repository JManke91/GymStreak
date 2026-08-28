//
//  SwiftDataHistorySnapshotStore.swift
//  GymStreak
//

import Foundation
import OSLog
import SwiftData

/// Constructs the SwiftData model actor outside MainActor, then forwards structured reads to it.
///
/// `AppDependencies` is MainActor, and direct construction there ran this store on the main thread
/// in the 240-session heartbeat test. Apple does not document construction-site affinity as a
/// `@ModelActor` guarantee, so `Task.detached` provides the explicit non-MainActor construction
/// contract. It is deliberately limited to constructing the stable actor: it does not receive or
/// process models, and actual fetch tasks retain normal caller cancellation through the actor
/// methods and their explicit cancellation checks.
struct SwiftDataHistorySnapshotProvider: HistorySnapshotProviding,
                                        LifetimeTrainingTotalsProviding,
                                        ExerciseDeepDiveFactProviding {
    private let storeTask: Task<SwiftDataHistorySnapshotStore, Never>

    init(modelContainer: ModelContainer) {
        self.storeTask = Task.detached(priority: .userInitiated) {
            SwiftDataHistorySnapshotStore(modelContainer: modelContainer)
        }
    }

    // MARK: - Off-main guarantee
    //
    // `@concurrent` (SE-0461) on **every method of this provider** is LOAD-BEARING — it
    // is the whole reason this type exists, and it applies to each one added since,
    // whichever protocol the method belongs to. `SWIFT_APPROACHABLE_CONCURRENCY` enables
    // `nonisolated(nonsending)` by default, which makes a plain `nonisolated async`
    // method run on the *caller's* actor. Called from a `@MainActor` ViewModel that
    // ran the entire unbounded fetch + aggregation ON the main actor, reproducing
    // the hang documented in `docs/history-performance.md` (measured ~600 ms by
    // `largeSnapshotBuildKeepsMainActorResponsive`). `@concurrent` restores the
    // unconditional "always leave the caller's actor" contract.
    //
    // Put it on these CONCRETE methods. Whether annotating the
    // `HistorySnapshotProviding` *requirements* would also work is NOT DOCUMENTED —
    // SE-0461 never discusses protocol witnesses — so it is not relied on. (An earlier
    // version of this comment claimed the requirement spelling was measured not to
    // work; that claim was retracted, because the measurement in question called the
    // concrete provider directly and so could not have exercised the protocol path.
    // See `docs/swift6-concurrency.md` §1 and §9b — do not reinstate it.)
    // Do not remove these annotations; if you think they are redundant, run the
    // regression test first.
    //
    // Re-measured 2026-08-13 while adding `fetchExerciseProgress`: dropping only that
    // method's `@concurrent` stalled the main actor **307 ms** in
    // `largeExerciseProgressBuildKeepsMainActorResponsive` (240 sessions × 5 exercises
    // × 4 sets); with it, under the 100 ms budget. The build was green either way.
    //
    // Re-measured again 2026-08-14 while adding `fetchPreviousPerformances`: dropping
    // only that method's `@concurrent` stalled the main actor **213 ms** in
    // `previousPerformanceLookupKeepsMainActorResponsive` (same seed, an eight-exercise
    // lookup). Green build either way, again.
    @concurrent func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        let store = await storeTask.value
        return try await store.fetchTrainingSnapshot(referenceDate: referenceDate)
    }

    @concurrent func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] {
        let store = await storeTask.value
        return try await store.fetchFortschrittSnapshot()
    }

    @concurrent func fetchPRDetails(
        sessionID: UUID
    ) async throws -> [UUID: PersonalRecordService.PRDetail] {
        let store = await storeTask.value
        return try await store.fetchPRDetails(sessionID: sessionID)
    }

    @concurrent func fetchExerciseProgress(
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int,
        usageSelection: ExerciseUsageSelection?
    ) async throws -> ExerciseProgressSnapshot {
        let store = await storeTask.value
        return try await store.fetchExerciseProgress(
            exerciseName: exerciseName,
            exerciseId: exerciseId,
            startDate: startDate,
            recentSessionLimit: recentSessionLimit,
            usageSelection: usageSelection
        )
    }

    @concurrent func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] {
        let store = await storeTask.value
        return try await store.fetchPreviousPerformances(lookup)
    }

    /// `LifetimeTrainingTotalsProviding`. A counting query, not an aggregation —
    /// still `@concurrent`, because it still enters the model actor.
    @concurrent func fetchCompletedWorkoutCount() async throws -> Int {
        let store = await storeTask.value
        return try await store.fetchCompletedWorkoutCount()
    }

    /// `LifetimeTrainingTotalsProviding`. `@concurrent` for the same
    /// load-bearing reason as the five above — this one walks *every* completed
    /// session's set graph, so it is the largest of them.
    @concurrent func fetchLifetimeTotals() async throws -> LifetimeTrainingTotals {
        let store = await storeTask.value
        return try await store.fetchLifetimeTotals()
    }

    /// `ExerciseDeepDiveFactProviding`. The cheap half — a bounded prefetch that stops at
    /// the newest matching session — but still `@concurrent`, because "cheap" is a claim
    /// about the common case and this one runs from a `.task` on every screen open.
    @concurrent func fetchDeepDiveCacheTimestamp(
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection
    ) async -> Date? {
        let store = await storeTask.value
        return await store.fetchDeepDiveCacheTimestamp(
            exerciseId: exerciseId,
            usageSelection: usageSelection
        )
    }

    /// `ExerciseDeepDiveFactProviding`. `@concurrent` for the same load-bearing reason as
    /// every method above: this walks all of completed history, faulting each matching
    /// row's sets, and until ticket 02 it did exactly that on the main actor — reached
    /// from a `Task { }` created on a `@MainActor` ViewModel, where SE-0461 leaves a plain
    /// `nonisolated` call.
    ///
    /// Measured 2026-08-28: dropping only this annotation stalled the main actor
    /// **311 ms** in `exerciseDeepDiveAggregationKeepsMainActorResponsive` (240 sessions ×
    /// 5 exercises × 4 sets, plus the live library entry). Build green either way.
    @concurrent func fetchDeepDiveAggregate(
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale
    ) async -> ExerciseDeepDiveAggregate {
        let store = await storeTask.value
        return await store.fetchDeepDiveAggregate(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            usage: usage,
            locale: locale
        )
    }
}

/// Actor-confined read model for the History feature.
///
/// Every unbounded fetch, relationship fault and whole-history aggregation happens on this
/// SwiftData executor. No `PersistentModel` crosses the boundary; callers receive immutable,
/// `Sendable` snapshots and resolve a single main-context model by UUID only for detail/delete.
/// Deliberately does **not** conform to `HistorySnapshotProviding`, despite having
/// matching methods. `SwiftDataHistorySnapshotProvider` above is the only boundary
/// type, and nothing ever injected the actor as the protocol.
///
/// The conformance was a live hazard rather than merely vestigial: it made the actor
/// an injectable `any HistorySnapshotProviding` whose methods carry no `@concurrent`,
/// so wiring it into `AppDependencies` instead of the provider would have restored
/// the ~600 ms main-actor hang with a green build and no warning. Removing it means
/// every route into this store goes through the provider's `@concurrent` hop.
/// Do not re-add it.
///
/// ## Every method body must stay free of internal `await`
///
/// This one actor serves several screens (Trainings, Fortschritt, a workout's PR
/// details, the exercise detail chart), so two calls can legitimately be in flight at
/// once — e.g. the History tab reloading while the pushed chart loads. Swift actors are
/// reentrant **only at suspension points**: a method that never `await`s internally is
/// guaranteed to run to completion before the next enqueued call is dequeued, which is
/// what makes sharing this actor safe with a single non-`Sendable` `ModelContext`.
/// Every fetch below is synchronous, so that holds today. **Adding an `await` inside any
/// of these methods would open an interleaving window on the shared context** — split it
/// into a separate actor instead, or hoist the awaited work to the caller.
@ModelActor
actor SwiftDataHistorySnapshotStore {
    private let signposter = OSSignposter(
        subsystem: "com.shotat24fps.GymStreak",
        category: "History"
    )

    /// Stateless value type; it holds no context of its own and reads this actor's.
    private let deepDive = ExerciseDeepDiveAggregator()

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        let routines = try measured("HistoryFetchRoutines") {
            var descriptor = FetchDescriptor<Routine>()
            descriptor.relationshipKeyPathsForPrefetching = [\.schedules]
            return try modelContext.fetch(descriptor)
        }

        try Task.checkCancellation()
        let prs = measured("HistoryBuildPRs") {
            PersonalRecordService.computePRs(sessions: sessions)
        }

        try Task.checkCancellation()
        let snapshot = measured("HistoryBuildTrainings") {
            HistorySnapshotBuilder.build(
                sessions: sessions,
                routines: routines,
                prCountBySession: prs.prCountBySession,
                referenceDate: referenceDate
            )
        }
        try Task.checkCancellation()
        return snapshot
    }

    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        let exercises = try measured("HistoryFetchExercises") {
            try modelContext.fetch(FetchDescriptor<Exercise>())
        }

        try Task.checkCancellation()
        let result = measured("HistoryBuildFortschritt") {
            FortschrittAggregator.build(sessions: sessions, liveExercises: exercises)
        }
        try Task.checkCancellation()
        return result
    }

    func fetchPRDetails(
        sessionID: UUID
    ) async throws -> [UUID: PersonalRecordService.PRDetail] {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        try Task.checkCancellation()
        let prs = measured("HistoryBuildPRs") {
            PersonalRecordService.computePRs(sessions: sessions)
        }
        try Task.checkCancellation()
        return prs.prDetailsBySession[sessionID] ?? [:]
    }

    /// Chart series + recent sessions for one exercise (audit P1.2).
    ///
    /// Reuses the same prefetch-correct `fetchCompletedSessions()` as the two snapshots
    /// above and windows by `startDate` **in Swift**, deliberately rather than in the
    /// `FetchDescriptor`. Narrowing the fetch would need a comparison across the
    /// optional `WorkoutExercise.workoutSession` relationship in the warm-up pass's
    /// `#Predicate`; SwiftData does not document support for that shape, and the
    /// reported failure mode is silently wrong results rather than a thrown
    /// `unsupportedPredicate`. The cost this finding was about — an unbounded fetch plus
    /// a full relationship traversal — is paid on this executor now, not on the main one.
    func fetchExerciseProgress(
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int,
        usageSelection: ExerciseUsageSelection?
    ) async throws -> ExerciseProgressSnapshot {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        let exercises = try measured("HistoryFetchExercises") {
            try modelContext.fetch(FetchDescriptor<Exercise>())
        }
        let liveSlotIds = try measured("HistoryFetchRoutineSlots") {
            try fetchLiveRoutineSlotIds()
        }

        try Task.checkCancellation()
        let snapshot = measured("HistoryBuildExerciseProgress") {
            ExerciseProgressAggregator.buildSnapshot(
                sessions: sessions,
                liveExercises: exercises,
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                startDate: startDate,
                recentSessionLimit: recentSessionLimit,
                liveRoutineSlotIds: liveSlotIds,
                requestedUsage: usageSelection
            )
        }
        try Task.checkCancellation()
        return snapshot
    }

    /// Every exercise of one workout resolved against its predecessor (audit P1.6).
    ///
    /// The replaced `ExerciseProgressService.compareWithPrevious` ran on the main actor
    /// and issued one unbounded, unprefetched fetch **per exercise**; this issues one
    /// prefetch-correct fetch for the whole workout, on this executor.
    ///
    /// Only the previous side lives here. The workout being compared stays with the
    /// caller as a main-context `@Model` — an `@ModelActor` cannot accept one, and
    /// re-fetching it by id would bet on cross-context visibility of changes the main
    /// context may not have saved (see `PreviousPerformanceLookup`). That bet would fail
    /// silently, as an empty comparison rather than an error.
    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        let exercises = try measured("HistoryFetchExercises") {
            try modelContext.fetch(FetchDescriptor<Exercise>())
        }

        try Task.checkCancellation()
        let resolved = measured("HistoryResolvePreviousPerformances") {
            PreviousPerformanceResolver.resolve(
                lookup: lookup,
                sessions: sessions,
                liveExercises: exercises
            )
        }
        try Task.checkCancellation()
        return resolved
    }

    /// How many completed workouts exist — §8 placement B's trigger question.
    ///
    /// Deliberately does **not** go through `fetchCompletedSessions()`. This runs
    /// after every completed workout, and the full-graph fetch would put an
    /// unbounded walk on this actor ahead of the History tab's own post-workout
    /// refetch, which `completeWorkout` invalidates a few lines earlier.
    /// `fetchCount` answers from the store without materializing a session.
    func fetchCompletedWorkoutCount() async throws -> Int {
        try Task.checkCancellation()
        return try measured("HistoryCountCompletedSessions") {
            try CompletedSessionFetch.completedCount(in: modelContext)
        }
    }

    /// All-time totals for §8 placement B's endowed figures.
    ///
    /// Reuses the same prefetch-correct fetch as every other read here, so the
    /// numbers the paywall shows are derived from exactly the graph the History
    /// tab renders — an off-by-one against the user's own screen is the one
    /// failure this placement cannot survive.
    func fetchLifetimeTotals() async throws -> LifetimeTrainingTotals {
        try Task.checkCancellation()
        let sessions = try measured("HistoryFetchSessions") {
            try fetchCompletedSessions()
        }
        try Task.checkCancellation()
        let totals = measured("HistoryBuildLifetimeTotals") {
            LifetimeTotalsAggregator.build(sessions: sessions)
        }
        try Task.checkCancellation()
        return totals
    }

    // MARK: - AI Coach exercise deep-dive

    /// The cache probe behind the exercise detail screen's narrative.
    ///
    /// Lives on this actor rather than the chat's (`ChatFactStore`) because the screen
    /// asking the question is the one this actor already serves: `fetchExerciseProgress`
    /// draws the chart the narrative sits under, from the same sessions. A second context
    /// would fault the same graph twice for one screen — and the chat actor is built
    /// lazily on first chat open, which the exercise detail screen never triggers.
    func fetchDeepDiveCacheTimestamp(
        exerciseId: UUID,
        usageSelection: ExerciseUsageSelection
    ) async -> Date? {
        // Cancellation degrades to "nothing found" rather than throwing, because this
        // boundary does not throw (see `ExerciseDeepDiveFactProviding`). It is worth
        // checking: `checkCache` runs from a `.task(id:)` cancelled on every exercise or
        // usage switch, and this actor is shared with the chart load that same switch
        // just started — so a superseded probe would queue ahead of it.
        guard !Task.isCancelled else { return nil }
        return measured("DeepDiveCacheTimestamp") {
            deepDive.lastCompletedSetTimestamp(
                exerciseId: exerciseId,
                modelContext: modelContext,
                usageSelection: usageSelection
            )
        }
    }

    /// The narrative's input and its cache timestamp, from one walk of history.
    ///
    /// The widest read on this actor after `fetchLifetimeTotals`: every completed session,
    /// every row matching the exercise, every completed set — plus a second all-time pass
    /// over the usages when the view is `.combined`.
    func fetchDeepDiveAggregate(
        exerciseId: UUID,
        exerciseName: String,
        usage: DeepDiveUsage,
        locale: Locale
    ) async -> ExerciseDeepDiveAggregate {
        // Same degradation as above. The caller (`ExerciseDeepDiveViewModel.run`) checks
        // cancellation itself before acting on this, so an empty aggregate never reaches
        // the screen as `.insufficientData`.
        guard !Task.isCancelled else {
            return ExerciseDeepDiveAggregate(lastCompletedSetTimestamp: nil, input: nil)
        }
        return measured("DeepDiveBuildAggregate") {
            deepDive.buildAggregate(
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                locale: locale,
                modelContext: modelContext,
                usage: usage
            )
        }
    }

    /// The prefetch-correct completed-session fetch, shared with the AI-coach fact actor.
    ///
    /// The two-step warm-up it performs used to live here; audit P1.3 moved it to
    /// `CompletedSessionFetch` when a second model actor needed the same graph, so the
    /// undocumented identity-map bet it makes is written down in exactly one place.
    private func fetchCompletedSessions() throws -> [WorkoutSession] {
        try CompletedSessionFetch.withFullGraph(in: modelContext)
    }

    /// Every routine slot the user still holds — what tells a usage the chart can still
    /// be trained apart from one only history remembers.
    ///
    /// Fetched from `Routine` rather than from `RoutineExercise` so "live" means what the
    /// user sees: a slot belongs to a routine that exists. `routineExercises` is
    /// prefetched because this walks it for every routine, and returning ids alone keeps
    /// the boundary `Sendable` — no `@Model` leaves this actor.
    ///
    /// Bounded by the routine library (dozens of slots), not by history, so it is a far
    /// smaller fetch than the completed-session graph it sits next to.
    private func fetchLiveRoutineSlotIds() throws -> Set<UUID> {
        var descriptor = FetchDescriptor<Routine>()
        descriptor.relationshipKeyPathsForPrefetching = [\.routineExercises]
        return Set(try modelContext.fetch(descriptor).flatMap { $0.routineExercisesList.map(\.id) })
    }

    private func measured<Result>(
        _ name: StaticString,
        operation: () throws -> Result
    ) rethrows -> Result {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }
}
