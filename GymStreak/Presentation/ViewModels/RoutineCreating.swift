//
//  RoutineCreating.swift
//  GymStreak
//
//  The one seam a new routine is written through, named so a second creation entry
//  point can depend on it without depending on the whole routines list.
//

import Foundation

/// Creating a routine template, and whether the free tier still permits one.
///
/// `RoutinesViewModel` satisfies this as it already stands — both members exist there
/// and neither changes. The protocol is not a new write path; it is a *name* for the
/// existing one, so the AI routine draft (docs/ai-coach-routine-drafting.md) can create
/// a routine through exactly the transaction the Create-Routine screen uses, and so the
/// draft's preflight can be asserted in a test without a `ModelContext`.
///
/// The cap is declared here beside the creation call on purpose: a creation entry point
/// that can read one but not the other is an entry point that can let a person build
/// something that cannot be saved.
@MainActor
protocol RoutineCreating: AnyObject {

    /// `true` when saving another routine template would go past the free cap — and for
    /// a lapsed user already above it, who keeps every routine they made but may not add
    /// to them.
    var isRoutineCapReached: Bool { get }

    /// Persists a brand-new routine with its exercises, sets and alternatives in one
    /// transaction, then refreshes the list — which is what pushes it to the watch.
    func createRoutine(name: String, pendingExercises: [PendingRoutineExercise])
}

/// Zero-body conformance: `RoutinesViewModel` already is this.
extension RoutinesViewModel: RoutineCreating {}
