//
//  ChatFactStore.swift
//  GymStreak
//
//  Off-main read boundary for the chat tools (audit P1.3). Replaces the
//  `@MainActor` `ChatFactService`, which fetched every completed session with no
//  prefetching and then walked session × exercise × set on the main actor — live,
//  mid-conversation, while the answer was streaming.
//
//  Fetching lives here; every fact line is built by `ChatFactBuilder`
//  (`Domain/Services/AICoach/`), so this file stays a thin persistence shell.
//

import Foundation
import os
import SwiftData

/// Constructs the SwiftData model actor outside MainActor, then forwards the three
/// tool fact lookups to it.
///
/// A direct port of `SwiftDataHistorySnapshotProvider` — see that type and
/// `docs/swift6-concurrency.md` §1 for why both halves of the trick are load-bearing.
/// In short: `@ModelActor` construction is sensitive to *where* it happens and Apple
/// documents no off-main guarantee for its synthesised executor, so `Task.detached`
/// gives the explicit non-MainActor construction contract, and `@concurrent` gives the
/// explicit "leave the caller's actor" contract on the way in.
struct ChatFactProvider: ChatFactProviding {
    private let storeTask: Task<ChatFactStore, Never>

    init(modelContainer: ModelContainer) {
        self.storeTask = Task.detached(priority: .userInitiated) {
            ChatFactStore(modelContainer: modelContainer)
        }
    }

    // MARK: - Off-main guarantee
    //
    // `@concurrent` (SE-0461) on all three methods is LOAD-BEARING and must sit on
    // these CONCRETE methods, not on the `ChatFactProviding` requirements — whether
    // annotating a requirement propagates to its witness is undocumented
    // (`docs/swift6-concurrency.md` §9b), so it is not relied on.
    //
    // Without it, `SWIFT_APPROACHABLE_CONCURRENCY`'s `nonisolated(nonsending)` default
    // makes these run on the *caller's* actor — and we deliberately do not depend on
    // knowing which actor that is. Apple declares the `Tool.call(arguments:)`
    // *requirement* `@concurrent` (researched 2026-08-13 against the iOS 26 reference),
    // but our three tools do not annotate their own `call`, and whether a requirement's
    // spelling governs an unannotated witness is the same undocumented question as
    // above. `@concurrent` here makes it moot: the fetch leaves the caller's actor
    // unconditionally, whichever actor that turns out to be. Guaranteeing it once, at
    // the boundary that owns the cost, beats annotating every caller.
    //
    // `chatFactLookupKeepsMainActorResponsive` in `SwiftDataHistorySnapshotStoreTests`
    // is the acceptance criterion, and it is not theoretical: deleting `@concurrent`
    // from `exercisePRFacts` alone stalled the main actor **319 ms** at 240 sessions
    // (measured 2026-08-13), with the build green either way. Do that once yourself
    // before concluding an annotation here is redundant.

    @concurrent func nextWorkoutFacts() async -> String {
        let store = await storeTask.value
        return await store.nextWorkoutFacts()
    }

    @concurrent func exercisePRFacts(exerciseName: String) async -> String {
        let store = await storeTask.value
        return await store.exercisePRFacts(exerciseName: exerciseName)
    }

    @concurrent func workoutHistoryFacts(timeframe: ChatHistoryTimeframe) async -> String {
        let store = await storeTask.value
        return await store.workoutHistoryFacts(timeframe: timeframe)
    }
}

/// Actor-confined read model for the chat tools.
///
/// No `PersistentModel` crosses the boundary — the tools receive fact `String`s.
/// Deliberately does **not** conform to `ChatFactProviding`: `ChatFactProvider` above
/// is the only boundary type, and a conforming actor would be an injectable
/// `any ChatFactProviding` whose methods carry no `@concurrent`, which would restore
/// the main-actor cost with a green build. Same reasoning as
/// `SwiftDataHistorySnapshotStore`; do not add the conformance.
///
/// ## Why a second `@ModelActor` rather than reusing the History store
///
/// `HistorySnapshotProviding` argues against splitting *one screen's* data across two
/// actors, and that still holds. This is the opposite case, and the trade is different:
///
/// - The History store's protocol is the History read boundary, returning display
///   snapshots. English fact lines for an on-device model do not belong in it.
/// - Chat tool calls fire mid-stream, when latency is most visible. A shared actor
///   serialises them behind a whole-history snapshot build (~300 ms measured); two
///   actors let them proceed in parallel.
/// - The AI coach is opt-in and gated on Apple Intelligence hardware, so its context
///   should not exist at all for most users. A shared actor cannot express that.
///
/// The cost accepted in exchange is a second `ModelContext` registering the same rows.
/// It is read-only and never saves, and `AppDependencies.makeChatFactProvider()` is a
/// factory precisely so it is never built at launch — but note the lifetime is
/// **app-lifetime after the first chat open**, not screen-lifetime: `CoachChatService`
/// is a singleton, holds the provider inside its `tools`, and `reset()` does not clear it.
///
/// ## Every method body must stay free of internal `await`
///
/// Two tool calls can be in flight within one turn. Swift actors are reentrant **only
/// at suspension points**, so a method that never `await`s internally runs to completion
/// before the next is dequeued — that is what makes a single non-`Sendable`
/// `ModelContext` safe here. Every fetch below is synchronous, so that holds today.
/// **Adding an `await` inside any of these methods would open an interleaving window on
/// the shared context.**
///
/// ## Fetch failures degrade to empty, they do not throw
///
/// These methods return `String`, not `throws`, because a tool must always hand the
/// model *something*; a thrown error mid-turn surfaces as a failed answer. A failed
/// fetch therefore yields the same fact line an empty database would — matching the
/// behaviour of the `try?`-based `ChatFactService` this replaces, but logged (see
/// `fetched(_:_:)`) rather than swallowed.
@ModelActor
actor ChatFactStore {

    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "ChatFactStore")

    func nextWorkoutFacts() async -> String {
        // `\.schedule` is read for every routine — a single direct key path, so this is
        // the documented use of prefetching, not the identity-map bet `withFullGraph` makes.
        var routineDescriptor = FetchDescriptor<Routine>()
        routineDescriptor.relationshipKeyPathsForPrefetching = [\.schedule]
        let routines = fetched("routines") { try modelContext.fetch(routineDescriptor) }
        // Only `startTime` and the owning routine are read, so the full exercise/set
        // graph is deliberately not faulted here.
        let sessions = fetched("sessions") { try CompletedSessionFetch.withRoutine(in: modelContext) }
        return ChatFactBuilder.nextWorkoutFacts(routines: routines, completedSessions: sessions)
    }

    func exercisePRFacts(exerciseName: String) async -> String {
        let library = fetched("library") { try modelContext.fetch(FetchDescriptor<Exercise>()) }
        let sessions = fetched("sessions") { try CompletedSessionFetch.withFullGraph(in: modelContext) }
        return ChatFactBuilder.exercisePRFacts(
            exerciseName: exerciseName,
            library: library,
            completedSessions: sessions
        )
    }

    func workoutHistoryFacts(timeframe: ChatHistoryTimeframe) async -> String {
        // `WorkoutSession.totalVolume` walks exercises → sets, so this one needs the graph.
        let sessions = fetched("sessions") { try CompletedSessionFetch.withFullGraph(in: modelContext) }
        return ChatFactBuilder.workoutHistoryFacts(timeframe: timeframe, completedSessions: sessions)
    }

    /// Degrades a failed fetch to empty — but logs it, because the user-visible symptom
    /// is otherwise indistinguishable from an empty database: the model states "No
    /// routines are scheduled" with full confidence. A wrong-but-fluent answer is this
    /// feature's worst failure mode, so it must not be silent.
    private func fetched<T>(_ what: StaticString, _ fetch: () throws -> [T]) -> [T] {
        do {
            return try fetch()
        } catch {
            logger.error("chat fact fetch failed (\(what, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
