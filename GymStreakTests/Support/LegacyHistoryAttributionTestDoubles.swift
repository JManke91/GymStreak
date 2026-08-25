//
//  LegacyHistoryAttributionTestDoubles.swift
//  GymStreakTests
//

import Foundation
@testable import GymStreak

/// Records the attribution calls a ViewModel makes without touching a store.
///
/// Shared across the `ExerciseProgressViewModel` suites because every one of them has to
/// pass *something* for the write seam, and only the attribution tests care what it does.
final class RecordingLegacyHistoryAttribution: LegacyHistoryAttributing, @unchecked Sendable {
    /// `@unchecked` with a written invariant, per the escape-hatch ranking in CLAUDE.md:
    /// `attributeLegacyRows` deliberately carries **no** `@concurrent`, so under SE-0461 it
    /// runs on the caller's actor — the `@MainActor` test — and the array is only ever read
    /// after that same actor has resumed. There is no concurrent access to serialise.
    private(set) var calls: [(name: String, exerciseId: UUID)] = []
    /// Rows the next call reports as linked, or `nil` to make it throw.
    var rowsToReport: Int?

    init(rowsToReport: Int? = 0) {
        self.rowsToReport = rowsToReport
    }

    struct Failure: Error {}

    func attributeLegacyRows(named exerciseName: String, to exerciseId: UUID) async throws -> Int {
        calls.append((exerciseName, exerciseId))
        guard let rowsToReport else { throw Failure() }
        return rowsToReport
    }
}
