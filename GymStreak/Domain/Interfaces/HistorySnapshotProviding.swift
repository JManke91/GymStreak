//
//  HistorySnapshotProviding.swift
//  GymStreak
//

import Foundation

/// Read boundary for the History feature.
///
/// Implementations own their persistence context and never expose `PersistentModel` instances
/// across the async boundary. This keeps unbounded fetches, relationship faulting and aggregation
/// off the main actor while Presentation receives immutable values.
/// ⚠️ The off-main guarantee is NOT provided by this protocol. Under
/// `SWIFT_APPROACHABLE_CONCURRENCY` (SE-0461, `nonisolated(nonsending)` by
/// default) a plain `nonisolated async` requirement runs on the **caller's**
/// actor, so calling these from a `@MainActor` ViewModel would execute the whole
/// unbounded fetch + aggregation on the main actor — the hang documented in
/// `docs/history-performance.md`.
///
/// The guarantee lives on the conforming type instead: the concrete
/// `SwiftDataHistorySnapshotProvider` methods are `@concurrent`, which is verified to
/// keep the work off the main actor even through existential dispatch. Whether
/// annotating these *requirements* would also work is NOT DOCUMENTED — SE-0461 never
/// discusses protocol witnesses — so do not rely on it. **Any new conformer that does
/// real work must carry `@concurrent` on its own methods.**
/// See `docs/swift6-concurrency.md` §1.
protocol HistorySnapshotProviding: Sendable {
    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot
    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel]
    func fetchPRDetails(sessionID: UUID) async throws -> [UUID: PersonalRecordService.PRDetail]

    /// The exercise detail screen pushed from Fortschritt: chart series + recent sessions.
    ///
    /// Part of this boundary rather than a separate one because it reads the same
    /// completed-session graph the two snapshots above already fetch and prefetch, and
    /// because a second `@ModelActor` would mean a second `ModelContext` warming the
    /// same rows. Both halves come back in one call so the screen cannot render a chart
    /// and a session list built from two different fetches.
    ///
    /// - Parameters:
    ///   - startDate: chart window lower bound, computed by the caller (it depends on
    ///     `Calendar.current`). `Date.distantPast` for the "All" timeframe.
    ///   - recentSessionLimit: caps the recent-session list, which is all-time.
    func fetchExerciseProgress(
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int
    ) async throws -> ExerciseProgressSnapshot
}

extension Notification.Name {
    /// Posted after a successful local mutation to routine or exercise data that contributes to
    /// History snapshots. The app-lifetime History `WorkoutViewModel` translates this event into
    /// its lightweight version token; no SwiftData models or repositories cross ViewModel seams.
    static let historySourceDataDidChange = Notification.Name("historySourceDataDidChange")
}
