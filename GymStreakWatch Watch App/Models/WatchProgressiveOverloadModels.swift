//
//  WatchProgressiveOverloadModels.swift
//  GymStreakWatch Watch App
//
//  Wire contract for the template-only progressive-overload transaction kind
//  (progressive-overload-resurface ticket 04). It is a payload kind of the
//  generic `TemplateTransactionEnvelope` established by in-workout-editing
//  ticket 05 — it reuses that envelope's transaction id, sender epoch,
//  per-routine sequence, FIFO, receipts, acknowledgment, and routine authority
//  unchanged, and adds no queue, inbox, or protocol of its own.
//
//  Split out of `WatchTemplateTransactionModels.swift` to keep both files
//  within the repository's file-length convention (same reason
//  `WatchRoutineTemplateFold.swift` was split out of the sync models).
//
//  The WIRE STRUCTS are an IDENTICAL COPY in both targets —
//  `GymStreak/Data/Sync/` and `GymStreakWatch Watch App/Models/` — keep them in
//  sync. There is no watch unit-test target; the iOS test target covers this
//  logic through its copy.
//
//  The iOS copy additionally carries a Wire→Domain mapper at the bottom (same
//  split as `WatchModels.swift`). The watch has no Domain layer, so that
//  section does not exist here.
//

import Foundation

/// One template set's absolute before/after values.
///
/// Absolute — never a delta. Duplicate delivery of the same transaction must
/// not increment twice, so the receiver compares the CURRENT template value
/// against `expected` (stage `proposed`), against `proposed` (already
/// satisfied, idempotent), or rejects the whole transaction on a third value.
struct WatchTemplateSetChange: Codable, Equatable {
    let setID: UUID
    let expectedReps: Int
    let expectedWeight: Double
    let proposedReps: Int
    let proposedWeight: Double
}

/// A mid-workout (or, from ticket 05, post-workout summary) request to raise a
/// routine template's working weight for one exercise target.
///
/// It mutates the ROUTINE TEMPLATE only. It never carries, creates, or alters
/// workout history — the performance the user just recorded stays exactly as
/// performed and travels separately in the completed-workout payload.
///
/// Expected values are derived from the latest effective routine template
/// scheme, never from the active workout's performed values, so a template the
/// user edited on iPhone in the meantime is detected as a conflict instead of
/// being silently overwritten.
struct WatchProgressiveOverloadIntent: Codable, Equatable {
    /// Bumped only for a breaking payload change. A receiver that does not
    /// support the version rejects the transaction terminally rather than
    /// guessing at its meaning.
    ///
    /// CONSTRAINT: this graceful terminal rejection only works while
    /// `schemaVersion` is the vehicle for breaking changes to THIS kind. Adding
    /// a new `TemplateTransactionPayload` case instead fails earlier — at
    /// `WatchWorkoutInboxStore.store(transactionData:)`, which cannot decode the
    /// envelope at all — and falls back to the documented "retained in the
    /// watch's FIFO until iOS is upgraded" policy. Evolve this payload by
    /// bumping the version; reserve a new case for a genuinely new kind.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = WatchProgressiveOverloadIntent.currentSchemaVersion
    /// The routine slot (`RoutineExercise.id`) whose scheme is being raised.
    let routineExerciseID: UUID
    /// The performed alternative's own set scheme (`RoutineExerciseAlternative.id`),
    /// or nil for the primary slot scheme. Targets are always resolved by these
    /// stable IDs — never by display name — so alternative values can never be
    /// written into the primary scheme.
    let alternativeID: UUID?
    /// The rep-range minimum every affected set resets to.
    let targetRepMin: Int
    /// Every affected template set exactly once, in template order.
    let setChanges: [WatchTemplateSetChange]

    /// Wire invariants checked identically on both sides before any optimistic
    /// application or authoritative mutation. All set changes are one atomic
    /// intent — partial application is forbidden — so a malformed intent
    /// rejects entirely instead of being repaired.
    var isWellFormed: Bool {
        guard schemaVersion == Self.currentSchemaVersion else { return false }
        guard targetRepMin > 0 else { return false }
        guard !setChanges.isEmpty else { return false }
        let ids = setChanges.map(\.setID)
        guard Set(ids).count == ids.count else { return false }
        return setChanges.allSatisfy { change in
            // Applying an overload always resets reps to the range minimum, so
            // a change proposing anything else is an internally inconsistent
            // payload rather than a value the receiver should trust.
            change.proposedReps == targetRepMin
                && change.expectedReps > 0
                && change.expectedWeight.isFinite && change.expectedWeight >= 0
                && change.proposedWeight.isFinite && change.proposedWeight >= 0
        }
    }
}

extension WatchTemplateSetChange {
    /// Weight equality for wire values that made a JSON round trip. The
    /// tolerance is far below any meaningful weight step, so it can never mask
    /// a genuine third value — it only avoids a spurious conflict from a
    /// last-bit representation difference.
    static func weightsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}
