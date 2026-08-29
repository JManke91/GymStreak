//
//  HistoryStoreGate.swift
//  GymStreak
//

import Foundation

/// Mutual exclusion between History's unbounded `@ModelActor` graph walks and the
/// deletion of completed-session rows from any other `ModelContext`.
///
/// ## Why this exists
///
/// `SwiftDataHistorySnapshotStore` fetches the whole completed-session graph into its
/// own context and then walks `WorkoutSession → WorkoutExercise → WorkoutSet`
/// synchronously. If another context deletes one of those rows and saves *during* that
/// walk, the actor's next property read cannot resolve its backing row and SwiftData
/// traps:
///
/// ```
/// data store did not return a snapshot for: PersistentIdentifier(…/WorkoutExercise/p385)
/// SwiftData/BackingData.swift:1039: Fatal error: This model instance was invalidated
/// because its backing data could no longer be found the store.
/// ```
///
/// This shipped: the device's Core Data persistent history recorded two History
/// deletions four seconds apart (2026-08-29 00:19:10 and 00:19:14); the second one
/// landed while the rebuild the first one had triggered was still walking the graph.
///
/// ## Why serialization is the only fix
///
/// There is no API-level remedy. SwiftData has no query generations (Core Data's
/// `setQueryGenerationFrom(.current)` has no counterpart), `ModelContext` has no
/// `automaticallyMergesChangesFromParent`, `isDeleted` only ever reflects a delete
/// staged in the object's *own* context, and the trap is an unconditional `fatalError`
/// that no `do/catch` can reach. Apple DTS's answer to exactly this scenario is to
/// serialize the reads against the writes in the app. See `docs/history-delete-race.md`.
///
/// ## Contract
///
/// Exclusive (one holder at a time), FIFO, and **not reentrant** — a holder that takes the
/// gate again deadlocks. Readers are already serialized by the single history
/// model actor, so taking this exclusively costs them nothing beyond what that actor
/// already imposes.
///
/// ## Two entry points, deliberately not overloads
///
/// `withAccess` is the **readers'** entry point — the three `@ModelActor` history providers
/// (`SwiftDataHistorySnapshotStore`, `SwiftDataLegacyHistoryAttributionStore`,
/// `ChatFactStore`), whose bodies genuinely have to `await` their actor.
///
/// `withExclusiveAccess` is the **writers'** entry point — every ViewModel, seeder and
/// coordinator that deletes rows. Its closure is *not* `async`, so suspending inside a gated
/// write is a compile error instead of a permanent silent hang: the gate is not reentrant, so
/// a writer that suspends while a History rebuild queues behind it deadlocks the app with no
/// crash, no crash report, no log, and no test that can catch it.
///
/// The two names differ on purpose. As overloads the guard would be worthless: a synchronous
/// closure converts freely to `() async throws -> T`, so both candidates stay viable — the
/// synchronous one wins while the body is await-free, and the moment someone adds an `await`
/// it drops out and the `async` overload is silently selected instead. The deadlock would
/// compile exactly as it does today.
///
/// Every writer that can delete a row the History actor may be holding must take it. That
/// graph is wider than "completed sessions": the actor also fetches the **entire** `Exercise`
/// table (`SwiftDataHistorySnapshotStore.swift:254`, `:302`, `:344`) and every `Routine` with
/// `\.schedules` prefetched, and `fetchLiveRoutineSlotIds` walks `routine.routineExercisesList`.
/// So `Exercise`, `Routine`, `RoutineExercise` and `RoutineSchedule` deletions are in scope too
/// — not just `WorkoutSession`, `WorkoutExercise` and `WorkoutSet`.
///
/// **That is the rule, not a description of the current code.** Every such writer in the app
/// takes the gate today, but the rule is what a new one has to satisfy — and one exposure
/// stays permanently out of reach: CloudKit mirroring applies remote deletes on its own
/// context, which no app-level lock can serialize against. See "Known residual exposure" in
/// `docs/history-delete-race.md`.
///
/// For **`WorkoutSession`** rows specifically the membership test is the History fetches' own
/// predicate — **`endTime != nil`** — and that is deliberately *not* the same question as
/// "is this a past workout".
/// `WorkoutViewModel.pauseForCompletion()` persists `endTime` when the user taps Finish, and
/// automatically once the last set is completed, while the session stays `currentSession` and
/// fully editable; "Continue workout" never clears it. So an in-progress workout can already
/// be inside the actor's graph, and `WorkoutViewModel.withHistoryGateIfVisible` is the single
/// place that decides this: it takes the gate only when `endTime != nil`, which keeps ordinary
/// in-workout set edits free of any wait on a History rebuild.
///
/// (`SwiftDataLegacyHistoryAttributionStore` is a partial exception — its fetch filters on
/// `exerciseId == nil` and only then checks `endTime`, so it could in principle hold an
/// in-progress row. Every shipped write path sets `exerciseId`, so in practice it never does.)
actor HistoryStoreGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// `AppDependencies` owns the one shared instance; everywhere else, say so with
    /// `unshared()`.
    init() {}

    /// A gate that excludes nothing, for tests and previews that have no competing writer.
    ///
    /// Exists so opting out is visible at the call site. Handing a *second* gate to a real
    /// reader or writer is a silent failure — it compiles, it looks wired, and it serializes
    /// nothing — so the production initialisers take the gate explicitly rather than
    /// defaulting it.
    static func unshared() -> HistoryStoreGate { HistoryStoreGate() }

    /// The **readers'** entry point: runs an `async` `body` with exclusive access. Released on
    /// both the success and the throwing path; `body` must not itself call back into the gate.
    ///
    /// Writers use `withExclusiveAccess` instead — see "Two entry points" above.
    ///
    /// `nonisolated` so `body` runs on the caller's executor rather than this actor's:
    /// awaiting it *inside* the actor would let a second caller in through actor
    /// reentrancy, which is precisely the exclusion this type exists to provide.
    nonisolated func withAccess<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let value = try await body()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    /// The **writers'** entry point: runs a *synchronous* `body` with exclusive access.
    /// Released on both the success and the throwing path.
    ///
    /// The closure is non-`async` on purpose. Every gated write is a fetch/delete/save burst
    /// that has no reason to suspend, and because the gate is not reentrant a suspension in
    /// there is a silent deadlock rather than a diagnosable failure. Taking a synchronous
    /// closure turns that mistake into a compile error. See "Two entry points" above for why
    /// this is a separate name and not an overload of `withAccess`.
    nonisolated func withExclusiveAccess<T>(_ body: () throws -> T) async rethrows -> T {
        await acquire()
        do {
            let value = try body()
            await release()
            return value
        } catch {
            await release()
            throw error
        }
    }

    /// Deliberately not cancellation-aware. A cancelled History rebuild still takes its FIFO
    /// turn ahead of a queued delete — but it costs that delete **5 ms**, not a walk, because
    /// every `SwiftDataHistorySnapshotStore` method checks cancellation as its first statement
    /// (eight `try Task.checkCancellation()`, two non-throwing `guard !Task.isCancelled`) and
    /// so hands the gate straight on. Measured on device at the crash store's volume
    /// (`GymStreakTests/HistoryGateLatencyTests`, docs/history-delete-race.md "What the gate
    /// costs"). That is why the non-throwing `withCheckedContinuation` stays: it is what makes
    /// "every acquire is followed by exactly one release" unconditional, and it is being paid
    /// for with 5 ms. Note that `ChatFactStore` checks no cancellation, so a cancelled coach
    /// fact lookup does pay in full.
    private func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        // The closure runs synchronously on this actor before the suspension, so the
        // append cannot race another `acquire`.
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
