//
//  HistoryImporting.swift
//  GymStreak
//

import Foundation

/// Boundary of the workout-history import (docs/history-import.md).
///
/// The second write path into workout history outside of recording a workout (the
/// first is `LegacyHistoryAttributing`). It only ever **adds** sessions and custom
/// exercises; it never edits or deletes existing rows, and never writes to Apple Health.
///
/// ⚠️ Like the other history boundaries, this protocol does **not** provide the off-main
/// guarantee: under SE-0461 a plain `nonisolated async` requirement runs on the caller's
/// actor. The conforming type carries `@concurrent` on its own methods. See
/// `docs/swift6-concurrency.md` §1.
protocol HistoryImporting: Sendable {
    /// Reads and parses a Strong CSV export and measures it against the current history
    /// and library. Writes nothing.
    ///
    /// - Parameter url: a file-picker URL; security-scoped access is handled inside.
    func prepareStrongImport(from url: URL) async throws -> HistoryImportPreview

    /// Writes the previewed file into history. Idempotent: a workout whose start time and
    /// name already exist is skipped, so re-importing the same or an overlapping export
    /// adds nothing twice.
    ///
    /// - Parameters:
    ///   - weightUnit: the unit the file's weights are in; stored values are kilograms.
    ///   - progress: fraction of workouts processed, 0…1, called off the main actor.
    func importHistory(
        _ file: ParsedHistoryFile,
        weightUnit: WeightUnit,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> HistoryImportResult
}
