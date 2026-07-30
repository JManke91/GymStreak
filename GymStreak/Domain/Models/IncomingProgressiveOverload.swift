//
//  IncomingProgressiveOverload.swift
//  GymStreak
//
//  Domain-owned input for a progressive-overload template transaction arriving
//  from the watch (progressive-overload ticket 04).
//
//  Same boundary rule as `IncomingWatchWorkout`: the Domain layer never
//  references the Codable sync type. The Data layer decodes
//  `WatchProgressiveOverloadIntent` at the WatchConnectivity boundary and maps
//  it into this model, so the wire format can change without touching Domain.
//

import Foundation

/// One template set's absolute before/after values, as the Domain sees them.
struct IncomingTemplateSetChange {
    let setID: UUID
    let expectedReps: Int
    let expectedWeight: Double
    let proposedReps: Int
    let proposedWeight: Double

    /// Weight equality for values that made a JSON round trip. The tolerance is
    /// orders of magnitude below the smallest offered step (1.25), so it can
    /// never mask a genuine third value — it only avoids a spurious conflict
    /// from a last-bit representation difference.
    static func weightsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}

/// A request to raise a routine template's working weight for one exercise
/// target. It mutates the TEMPLATE only — it never carries, creates, or alters
/// workout history.
struct IncomingProgressiveOverload {
    /// False when the sender used a payload schema this build does not
    /// understand. Carried rather than mapped to nil so the receiver can still
    /// return a versioned terminal rejection instead of leaving the sender's
    /// transaction pending forever.
    let isSchemaSupported: Bool
    /// The routine slot (`RoutineExercise.id`) whose scheme is being raised.
    let routineExerciseID: UUID
    /// The performed alternative's own scheme (`RoutineExerciseAlternative.id`),
    /// or nil for the primary slot scheme.
    let alternativeID: UUID?
    /// The rep-range minimum every affected set resets to.
    let targetRepMin: Int
    /// Every affected template set exactly once, in template order.
    let setChanges: [IncomingTemplateSetChange]

    /// Invariants checked before any mutation. All set changes are one atomic
    /// intent — partial application is forbidden — so a malformed intent is
    /// rejected entirely rather than repaired.
    var isWellFormed: Bool {
        guard isSchemaSupported, targetRepMin > 0, !setChanges.isEmpty else { return false }
        let ids = setChanges.map(\.setID)
        guard Set(ids).count == ids.count else { return false }
        return setChanges.allSatisfy { change in
            // Applying an overload always resets reps to the range minimum, so
            // a change proposing anything else is internally inconsistent.
            change.proposedReps == targetRepMin
                && change.expectedReps > 0
                && change.expectedWeight.isFinite && change.expectedWeight >= 0
                && change.proposedWeight.isFinite && change.proposedWeight >= 0
        }
    }
}
