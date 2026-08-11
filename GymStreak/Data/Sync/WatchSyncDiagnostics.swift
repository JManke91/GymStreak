//
//  WatchSyncDiagnostics.swift
//  GymStreak
//
//  Structured, privacy-conscious logging for the watch → iOS workout delivery
//  path (durable outgoing queue → transport → receive inbox → ingestion →
//  acknowledgment) and the routine authority the acknowledgment depends on.
//
//  WHY THIS EXISTS: this path used `print()`, which writes to stderr and is
//  therefore invisible in Console.app for a device build — it can only be seen
//  with Xcode attached. The 2026-08-01 incident (a finalized workout silently
//  withheld behind an unretired FIFO head) consequently could not be diagnosed
//  from a support log at all; it took a debugger and two `po` calls. Everything
//  needed to reconstruct that failure now goes to unified logging instead.
//
//  Identifiers are logged as SHORTENED, one-way, launch-stable tokens — never
//  raw UUIDs, and never exercise names, weights, reps, or payload bytes. Rest
//  DURATIONS are the one deliberate exception (`restSummary`, and the rest lines
//  the merge emits): a template's rest time identifies nobody and reveals no
//  performance, and a 2026-08-11 failure — rest silently not persisting — could
//  not be localized to the watch, the transport or the merge without seeing the
//  performed/baseline pair at each hop. Values of any other kind stay out. The
//  token algorithm is deliberately identical to `WorkoutRecoveryDiagnostics`
//  (which delegates here), so a token seen under `WatchSync` and one seen under
//  `WorkoutRecovery` refer to the same object and support logs correlate across
//  both categories.
//
//  Unlike `WorkoutRecoveryDiagnostics`, this is a leveled message seam rather
//  than one typed method per event: the call sites it replaces are numerous and
//  their messages are already meaningful, so a 1:1 conversion keeps them
//  readable and reviewable. Callers own shortening any identifier they
//  interpolate — that is the privacy boundary.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Managers/` — keep them in sync. The watch target
//  needs it because the shared queue/transport files log from both.
//

import Foundation
import os

enum WatchSyncDiagnostics {
    private static let logger = Logger(
        subsystem: "com.shotat24fps.GymStreak", category: "WatchSync"
    )

    /// Deterministic, one-way 8-hex-char token for a UUID. FNV-1a rather than
    /// `Hasher`, which is per-process randomized — these must stay stable
    /// across launches so multi-session support logs correlate.
    static func shortID(_ uuid: UUID) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    static func shortID(_ uuid: UUID?) -> String {
        uuid.map(shortID) ?? "none"
    }

    /// Per-exercise `slot=performedRest/baselineRest` for a completed workout,
    /// as `<first set by order>`. This is the exact pair the rest-in-template
    /// intent is derived from on both sides of the wire, so logging it on the
    /// sender and again on the receiver localizes a "my rest did not sync"
    /// report to the watch, the transport, or the merge.
    static func restSummary(of workout: CompletedWatchWorkout) -> String {
        workout.exercises.map { exercise in
            let first = exercise.sets.min { $0.order < $1.order }
            let performed = first.map { String(Int($0.restTime)) } ?? "-"
            let baseline = first?.plannedRestTime.map { String(Int($0)) } ?? "nil"
            return "\(shortID(exercise.id))=\(performed)/\(baseline)"
        }.joined(separator: " ")
    }

    /// Routine progress through the pipeline.
    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Something the user or a future investigation should care about, but
    /// which the protocol handles (suppressed duplicate, retained payload,
    /// deferred work).
    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// A failure that leaves durable state replayable.
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// A terminal or liveness-threatening condition: data that can no longer
    /// converge on its own, or work stalled with no bounded escape.
    static func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}
